// Read-only chat metadata, cloud task listing and remote computer names. No prompts or chat mutations.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execFileAsync = promisify(execFile);
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

export function timestamp(value) {
  const n = Number(value);
  return Number.isFinite(n) ? (n > 1e11 ? n / 1000 : n) : (Date.parse(value) / 1000 || 0);
}
export function historyID(thread) {
  // Resumed branches keep their visible ID but project history under the
  // session UUID appended to the rollout filename.
  return thread.rollout_path?.match(/_([0-9a-f-]{36})\.jsonl$/i)?.[1] ?? thread.id;
}
export function stateOf(status, unread = false) {
  const type = typeof status === 'string' ? status : status?.type;
  const flags = typeof status === 'object' ? status?.activeFlags ?? [] : [];
  if (flags.some(x => /waiting.*(input|approval)|needs.*input/i.test(x)) || /waiting|needs.?input|approval/i.test(type ?? '')) return 'waiting for input';
  if (type === 'active' || type === 'running' || type === 'in_progress' || type === 'inProgress') return 'running';
  if (type === 'notified' || unread === true || status?.hasUnreadTurn === true) return 'notified';
  if (['idle', 'notLoaded', 'systemError', 'stopped', 'completed', 'interrupted', 'failed'].includes(type)) return 'stopped';
  return null;
}
export function unreadState(global, auth) {
  const buckets = global?.['electron-thread-read-state-v1'];
  if (buckets?.version !== 1) return () => undefined;
  let identity;
  for (const token of [auth?.tokens?.id_token, auth?.tokens?.access_token]) {
    try {
      const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
      const principal = claims['https://api.openai.com/auth'];
      const account = auth.tokens.account_id || principal?.chatgpt_account_id;
      const user = principal?.chatgpt_user_id || principal?.user_id;
      if (!account || !user) continue;
      const key = createHash('sha256').update(JSON.stringify(['chatgpt',account,user])).digest('hex');
      if (buckets.unreadByIdentity?.[key]) { identity = buckets.unreadByIdentity[key]; break; }
    } catch { /* Unsupported identity: retain explicit per-thread metadata only. */ }
  }
  return (hostId, id) => {
    if (!identity) return undefined;
    const entries = Object.entries(identity).filter(([key,ids]) => (key === hostId || key.startsWith(hostId + ':')) && Array.isArray(ids));
    return entries.length === 1 ? entries[0][1].includes(id) : undefined;
  };
}
export function chatKey(t) { return JSON.stringify([t.kind ?? 'codex', t.hostId ?? 'local', t.id]); }
export function validPins(raw) {
  if (!Array.isArray(raw)) return [];
  const unique = new Map();
  for (const t of raw) {
    if (typeof t?.id !== 'string' || !['codex','cloud'].includes(t.kind) || typeof t.hostId !== 'string' || !t.hostId || t.hostId.length > 256 || /[\x00-\x1f\x7f]/.test(t.hostId)) continue;
    if (t.kind === 'codex' ? !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t.id) : !/^[A-Za-z0-9_-]+$/.test(t.id)) continue;
    unique.set(chatKey(t),t);
    if (unique.size === 10) break;
  }
  return [...unique.values()];
}
export function originOf(t) {
  if (t.kind === 'chatgpt' || /cloud|hosted|environment-git/.test(t.hostId ?? '')) return 'Cloud';
  return !t.hostId || t.hostId === 'local' ? 'Mac' : 'Remote';
}
export function recentThreads(data, pins = []) {
  const unique = new Map();
  for (const t of [...data.pinnedThreads ?? [], ...data.threads ?? []]) {
    const key = chatKey(t);
    if (t.id && (!unique.has(key) || timestamp(t.updatedAt) > timestamp(unique.get(key).updatedAt))) unique.set(key, t);
  }
  const ranks = new Map(pins.map((t,index)=>[chatKey(t),index]));
  for (const pin of pins) if (!unique.has(chatKey(pin))) unique.set(chatKey(pin),{...pin,title:'Pinned chat',status:null,updatedAt:0});
  return [...unique.values()].sort((a,b) => (ranks.get(chatKey(a)) ?? 100) - (ranks.get(chatKey(b)) ?? 100) || timestamp(b.updatedAt) - timestamp(a.updatedAt)).slice(0,10);
}

function openDatabase(home, prefix) {
  const names = fs.readdirSync(home).filter(n => new RegExp(`^${prefix}_[0-9]+\\.sqlite$`).test(n))
    .sort((a,b) => Number(b.match(/_(\d+)/)[1])-Number(a.match(/_(\d+)/)[1]));
  if (!names.length) return null;
  return new DatabaseSync(path.join(home,names[0]), {readOnly:true});
}
function safeJSON(file) {
  try { return JSON.parse(fs.readFileSync(file,'utf8')); } catch { return null; }
}
// The same read-only computer catalog used by the installed Codex app. Keep only
// names; credentials stay in Codex's existing auth file and are never persisted here.
export function hostNamesFromCatalog(items) {
  const names = {};
  for (const item of Array.isArray(items) ? items : []) {
    if (typeof item?.env_id !== 'string' || !/^env_[A-Za-z0-9_-]+$/.test(item.env_id)) continue;
    const name = [item.host_name,item.name,item.display_name].find(v => typeof v === 'string' && v.trim());
    if (name) names['remote-control:' + item.env_id] = name.replace(/[\x00-\x1f\x7f]/g,' ').trim().slice(0,160);
  }
  return names;
}
export async function readRemoteHostNames({home,cachePath,now=Date.now(),fetcher=fetch}={}) {
  home ??= process.env.CODEX_HOME || path.join(os.homedir(),'.codex');
  cachePath ??= process.platform === 'win32'
    ? path.join(process.env.LOCALAPPDATA || path.join(os.homedir(),'AppData','Local'),'notchGPT','remote-hosts.json')
    : path.join(os.homedir(),'Library','Application Support','notchGPT','remote-hosts.json');
  const auth = safeJSON(path.join(home,'auth.json'));
  const token = auth?.tokens?.access_token, account = auth?.tokens?.account_id;
  if (typeof token !== 'string' || !token || typeof account !== 'string' || !account) return {};
  const accountDigest = createHash('sha256').update(account).digest('hex');
  const stored = safeJSON(cachePath);
  const cached = stored?.version === 1 && stored.accountDigest === accountDigest ? stored : {};
  const previous = Object.fromEntries(Object.entries(cached.hosts ?? {}).filter(([key,value]) =>
    /^remote-control:env_[A-Za-z0-9_-]+$/.test(key) && typeof value === 'string' && value.length <= 160));
  if (Number.isFinite(cached.nextCheckAt) && cached.nextCheckAt > now && cached.nextCheckAt <= now + 300000) return previous;
  let hosts = previous, fetchedAt = cached.fetchedAt ?? null, succeeded = false;
  try {
    const signal = AbortSignal.timeout(5000), result = {};
    let cursor = null;
    for (let page = 0; page < 3; page++) {
      const query = new URLSearchParams({limit:'100'});
      if (cursor) query.set('cursor',cursor);
      const response = await fetcher('https://chatgpt.com/backend-api/codex/remote/control/environments?' + query,
        {method:'GET',headers:{Authorization:'Bearer ' + token,'ChatGPT-Account-ID':account,Accept:'application/json'},redirect:'error',signal});
      if (!response.ok) throw Error('Computer catalog unavailable');
      const text = await response.text();
      if (text.length > 1024 * 1024) throw Error('Computer catalog too large');
      const data = JSON.parse(text);
      if (!Array.isArray(data.items)) throw Error('Invalid computer catalog');
      Object.assign(result,hostNamesFromCatalog(data.items));
      cursor = typeof data.cursor === 'string' && data.cursor ? data.cursor : null;
      if (!cursor) { hosts = result; fetchedAt = now; succeeded = true; break; }
    }
  } catch { /* Offline/expired session: retain the last names for this account. */ }
  try {
    fs.mkdirSync(path.dirname(cachePath),{recursive:true,mode:0o700});
    const temporary = cachePath + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary,JSON.stringify({version:1,accountDigest,fetchedAt,nextCheckAt:now + (succeeded ? 300000 : 60000),hosts}),{mode:0o600});
    fs.renameSync(temporary,cachePath);
  } catch { /* Name caching must never prevent chat display. */ }
  return hosts;
}
export function pendingInput(items) {
  return items.some(t => /inProgress|pending|waiting|requested/.test(t.status ?? '') &&
    /request.?user.?input|approval|elicitation/i.test(`${t.tool ?? ''} ${t.type ?? ''} ${t.status ?? ''}`));
}
export function cachedRemotes(atoms) {
  const result=[];
  for (const [key,value] of Object.entries(atoms)) {
    if (!key.startsWith('remote-thread-summaries-v3:') || !Array.isArray(value)) continue;
    for (const t of value) {
      if (t.threadSource === 'subagent' || typeof t.source === 'object') continue;
      result.push({id:t.conversationId,kind:'codex',hostId:t.hostId || key.slice('remote-thread-summaries-v3:'.length),
        title:t.title || t.preview?.split('\n')[0] || 'Untitled chat',updatedAt:t.updatedAt,status:t.threadRuntimeStatus,hasUnreadTurn:t.hasUnreadTurn});
    }
  }
  return result;
}
async function cloudTasks(cli) {
  if (!cli) throw Error('Cloud CLI unavailable');
  const {stdout} = await execFileAsync(cli, ['cloud','list','--json','--limit','10'], {timeout:7000,maxBuffer:1024*1024});
  const data=JSON.parse(stdout);
  return (data.tasks ?? []).map(t => ({id:t.id || t.task_id,kind:'cloud',hostId:'cloud',title:t.title || 'Cloud chat',url:typeof t.url === 'string' ? t.url : undefined,
    updatedAt: t.updated_at ?? t.updatedAt,
    status: t.status === 'ready' || t.status === 'failed' || t.status === 'error' ? 'stopped' : t.status === 'pending' || t.status === 'queued' ? 'running' : t.status}));
}
async function main() {
  const home=process.env.CODEX_HOME || path.join(os.homedir(),'.codex');
  const global=safeJSON(path.join(home,'.codex-global-state.json'));
  const atoms=global?.['electron-persisted-atom-state'] ?? {};
  const unread=unreadState(global,safeJSON(path.join(home,'auth.json')));
  let pins=[];
  try { pins=validPins(JSON.parse(process.env.NOTCHGPT_PINNED_CHATS || '[]')); } catch {}
  const loaded=process.env.NOTCHGPT_LOADED_THREADS ? new Set(JSON.parse(process.env.NOTCHGPT_LOADED_THREADS)) : null;
  const state=openDatabase(home,'state');
  const history=openDatabase(home,'thread_history');
  const result=[];
  let partial=!state || !history || !global;
  try {
    if(state) {
      const local=state.prepare(`SELECT id, rollout_path, COALESCE(NULLIF(name,''), title) AS title, updated_at AS updatedAt
        FROM threads WHERE archived=0 AND source IN ('vscode','cli','appServer','exec')
        AND COALESCE(thread_source,'') NOT IN ('subagent','guardian_review') ORDER BY updated_at DESC LIMIT 50`).all();
      const localPins=pins.filter(t=>t.kind==='codex' && t.hostId==='local');
      if (localPins.length) {
        local.push(...state.prepare(`SELECT id,rollout_path,COALESCE(NULLIF(name,''),title) AS title,updated_at AS updatedAt FROM threads
          WHERE archived=0 AND id IN (${localPins.map(()=>'?').join(',')}) AND COALESCE(thread_source,'') NOT IN ('subagent','guardian_review')`).all(...localPins.map(t=>t.id)));
      }
      let unreadQuery;
      try { unreadQuery=state.prepare('SELECT first_unread_turn FROM thread_read_receipts WHERE thread_id=?'); } catch {}
      const turnQuery=history?.prepare('SELECT turn_id,status FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1');
      const itemQuery=history?.prepare(`SELECT item_type AS type, json_extract(item_json,'$.tool') AS tool,
        json_extract(item_json,'$.status') AS status FROM thread_items WHERE thread_id=? AND turn_id=?
        ORDER BY rollout_ordinal DESC LIMIT 120`);
      for(const t of local) {
        if(atoms[`codex-writing-block-deleted-thread-v1:${t.id}`]) continue;
        const projectedID=historyID(t);
        const turn=turnQuery?.get(projectedID);
        let status=turn?.status ?? null;
        if(status === 'inProgress') {
          if(loaded && !loaded.has(t.id)) status='stopped';
          else if(pendingInput(itemQuery?.all(projectedID,turn.turn_id) ?? [])) status='waiting for input';
        }
        result.push({...t,kind:'codex',hostId:'local',status,hasUnreadTurn:unread('local',t.id) ?? (unreadQuery?.get(projectedID)?.first_unread_turn != null)});
      }
    }
  } finally { state?.close(); history?.close(); }
  result.push(...cachedRemotes(atoms));
  const apps=['/Applications/ChatGPT.app',path.join(os.homedir(),'Applications/ChatGPT.app'),'/Applications/Codex.app',path.join(os.homedir(),'Applications/Codex.app')];
  const cli=process.env.CODEX_BIN || apps.map(p=>path.join(p,'Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex')).find(p=>fs.existsSync(p));
  try { result.push(...await cloudTasks(cli)); } catch { partial=true; }
  const recent = recentThreads({threads:result},pins);
  const names = recent.some(t => originOf(t) === 'Remote') ? await readRemoteHostNames({home}) : {};
  const threads=recent.map(t=>({id:t.id,title:t.title,state:stateOf(t.status,unread(t.hostId ?? 'local',t.id) ?? t.hasUnreadTurn),origin:originOf(t),hostId:t.hostId,hostName:names[t.hostId],kind:t.kind,url:typeof t.url === 'string' ? t.url : undefined,updatedAt:timestamp(t.updatedAt)}));
  if(!threads.length && partial) throw Error('Chat unavailable');
  process.stdout.write(JSON.stringify({threads,partial,cached:true}));
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main().catch(() => { process.stdout.write(JSON.stringify({error:'Chats unavailable. Open Codex and retry.'})); process.exitCode=1; });
}
