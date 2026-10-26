import assert from 'node:assert/strict';
import { stateOf,originOf,recentThreads,pendingInput,cachedRemotes,historyID,timestamp,hostNamesFromCatalog,readRemoteHostNames,unreadState,validPins,chatKey } from '../../Resources/recent-chats.mjs';
assert.equal(stateOf({type:'active',activeFlags:[]}), 'running');
assert.equal(stateOf({type:'active',activeFlags:['waitingOnUserInput']}), 'waiting for input');
assert.equal(stateOf({type:'active',activeFlags:['waitingOnApproval']}), 'waiting for input');
for(const type of ['idle','notLoaded','systemError']) assert.equal(stateOf(type),'stopped');
assert.equal(stateOf('futureUnknownStatus'),null);
assert.equal(originOf({hostId:'local'}),'Mac');
assert.equal(originOf({hostId:'remote-control:test'}),'Remote');
assert.equal(originOf({kind:'chatgpt',hostId:'local'}),'Cloud');
assert.equal(originOf({hostId:'environment-git:hosted:test'}),'Cloud');
const threads=Array.from({length:12},(_,i)=>({id:String(i),hostId:'local',kind:'codex',updatedAt:1000+i}));
const result=recentThreads({threads,pinnedThreads:[{...threads[0],updatedAt:1013000*1000},threads[11]]});
assert.equal(result.length,10);
assert.equal(result[0].id,'0');
assert.equal(result[1].id,'11');
assert.equal(new Set(result.map(t=>t.id)).size,10);
assert.equal(recentThreads({threads:[]}).length,0);
console.log('PASS: recent chats: status flags, unknown status, origins, pinned merge, recency, deduplication, limit, empty data');

assert.equal(pendingInput([{tool:'request_user_input',status:'inProgress'}]),true);
assert.equal(pendingInput([{tool:'request_user_input',status:'completed'}]),false);
assert.equal(pendingInput([{type:'commandExecution',status:'inProgress'}]),false);
assert.equal(cachedRemotes({'remote-thread-summaries-v3:ssh:test':[{conversationId:'remote1',title:'Example',threadRuntimeStatus:{type:'idle'}},{conversationId:'child',threadSource:'subagent'}]}).length,1);
assert.equal(historyID({id:'visible',rollout_path:'/sessions/rollout-visible_00000000-0000-0000-0000-000000000001.jsonl'}),'00000000-0000-0000-0000-000000000001');
assert.equal(historyID({id:'visible',rollout_path:'/sessions/rollout-visible.jsonl'}),'visible');
assert.equal(timestamp('2026-10-22T12:00:00Z'),1792670400);

assert.deepEqual(hostNamesFromCatalog([
 {env_id:'env_pc1',host_name:'example-workstation',display_name:'Project alias'},
 {env_id:'env_pc2',host_name:' ',name:'example-host'},
 {env_id:'env_pc3',display_name:'example-server'},
 {env_id:'../invalid',host_name:'bad'},
 {env_id:'env_empty',host_name:null},
 {env_id:'env_clean',host_name:'PC\nname'}
]),{'remote-control:env_pc1':'example-workstation','remote-control:env_pc2':'example-host','remote-control:env_pc3':'example-server','remote-control:env_clean':'PC name'});
const fs = await import('node:fs');
const os = await import('node:os');
const path = await import('node:path');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(),'notchgpt-hosts-'));
try {
 const cachePath=path.join(temporary,'names.json'), home=path.join(temporary,'codex'); fs.mkdirSync(home);
 const authPath=path.join(home,'auth.json');
 fs.writeFileSync(authPath,JSON.stringify({tokens:{access_token:'test-token',account_id:'test-account'}}));
 const originalAuth=fs.readFileSync(authPath,'utf8');
 let calls=0;
 const fetcher=async (url,options)=>{
  calls++; assert.equal(new URL(url).origin,'https://chatgpt.com'); assert.equal(options.method,'GET'); assert.equal(options.redirect,'error');
  assert.equal(options.headers.Authorization,'Bearer test-token');
  return {ok:true,text:async()=>JSON.stringify({items:[{env_id:'env_pc',host_name:'example-host'}],cursor:null})};
 };
 assert.equal((await readRemoteHostNames({home,cachePath,now:1000,fetcher}))['remote-control:env_pc'],'example-host');
 await readRemoteHostNames({home,cachePath,now:16000,fetcher}); assert.equal(calls,1,'computer names are cached for five minutes');
 const offline=async()=>{throw Error('offline');};
 assert.equal((await readRemoteHostNames({home,cachePath,now:302000,fetcher:offline}))['remote-control:env_pc'],'example-host');
 const cache=fs.readFileSync(cachePath,'utf8');
 assert.ok(!cache.includes('test-token') && !cache.includes('test-account'),'cache must never contain credentials or raw account IDs');
 assert.equal(fs.readFileSync(authPath,'utf8'),originalAuth,'host lookup must not modify Codex sign-in');
 fs.writeFileSync(authPath,JSON.stringify({tokens:{access_token:'test-token',account_id:'other-account'}}));
 assert.deepEqual(await readRemoteHostNames({home,cachePath,now:320000,fetcher:offline}),{},'host cache must not cross accounts');
 let page=0;
 const paged=async()=>({ok:true,text:async()=>JSON.stringify({items:[{env_id:'env_page'+(++page),host_name:'PC'+page}],cursor:page===1?'page-two':null})});
 const pagedNames=await readRemoteHostNames({home,cachePath,now:400000,fetcher:paged});
 assert.equal(pagedNames['remote-control:env_page1'],'PC1'); assert.equal(pagedNames['remote-control:env_page2'],'PC2');
} finally { fs.rmSync(temporary,{recursive:true,force:true}); }
console.log('PASS: computer names: true host names, pagination, cache TTL, offline fallback, account isolation, no credential persistence or sign-in mutation');

assert.equal(stateOf('notified'),'notified');
assert.equal(stateOf('idle',true),'notified');
assert.equal(stateOf('notLoaded',true),'notified');
assert.equal(stateOf({type:'active',activeFlags:['waitingOnUserInput']},true),'waiting for input');
assert.equal(stateOf({type:'active',activeFlags:[]},true),'running');
assert.equal(stateOf('idle',false),'stopped');
const {createHash} = await import('node:crypto');
const principal=['chatgpt','account-test','user-test'];
const identity=createHash('sha256').update(JSON.stringify(principal)).digest('hex');
const token='header.'+Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_user_id:'user-test'}})).toString('base64url')+'.signature';
const readGlobal={'electron-thread-read-state-v1':{version:1,unreadByIdentity:{[identity]:{'local:device':['thread-unread'],'remote-control:env_test:identity':['remote-unread']},other:{'local:device':['other-account']}}}};
const readAuth={tokens:{account_id:'account-test',id_token:token}};
const isUnread=unreadState(readGlobal,readAuth);
assert.equal(isUnread('local','thread-unread'),true);
assert.equal(isUnread('local','other-account'),false);
assert.equal(isUnread('remote-control:env_test','remote-unread'),true);
assert.equal(isUnread('remote-control:env_other','remote-unread'),undefined);
assert.equal(unreadState(readGlobal,{tokens:{account_id:'other',id_token:token}})('local','thread-unread'),undefined);
readGlobal['electron-thread-read-state-v1'].unreadByIdentity[identity]['local:retired']=['thread-old'];
assert.equal(unreadState(readGlobal,readAuth)('local','thread-old'),undefined);
const pin={id:'00000000-0000-4000-8000-000000000001',hostId:'local',kind:'codex'};
assert.deepEqual(validPins([pin,pin,{...pin,id:'invalid'}]),[pin]);
const pinnedRecent=recentThreads({threads:[...threads,{...pin,updatedAt:1,title:'old'}]},[pin]);
assert.equal(pinnedRecent[0].id,pin.id);
assert.equal(pinnedRecent.length,10);
assert.notEqual(chatKey(pin),chatKey({...pin,hostId:'ssh:other'}));
assert.equal(recentThreads({threads:[]},[pin])[0].title,'Pinned chat');
console.log('PASS: notified: distinct status, input/running priority, account and host isolation; pins: identity, old chats, placeholders, ordering and limit');
