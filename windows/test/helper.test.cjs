"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  { execFileSync } = require("node:child_process");
const { DatabaseSync } = require("node:sqlite");
test("shared metadata helper reads isolated Windows-compatible databases without writing sign-in or chat state", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "notchgpt-isolated-"));
  try {
    const state = new DatabaseSync(path.join(home, "state_5.sqlite"));
    state.exec(
      `CREATE TABLE threads(id TEXT,rollout_path TEXT,name TEXT,title TEXT,updated_at INTEGER,archived INTEGER,source TEXT,thread_source TEXT);CREATE TABLE thread_read_receipts(thread_id TEXT,first_unread_turn TEXT);`,
    );
    const id = "00000000-0000-4000-8000-000000000001";
    state
      .prepare("INSERT INTO threads VALUES(?,?,?,?,?,?,?,?)")
      .run(
        id,
        null,
        "Example chat",
        "Example chat",
        1792670400,
        0,
        "appServer",
        "",
      );
    state
      .prepare("INSERT INTO thread_read_receipts VALUES(?,?)")
      .run(id, "unread-turn");
    state.close();
    const history = new DatabaseSync(
      path.join(home, "thread_history_1.sqlite"),
    );
    history.exec(
      `CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,status TEXT,rollout_ordinal INTEGER);CREATE TABLE thread_items(thread_id TEXT,turn_id TEXT,item_type TEXT,item_json TEXT,rollout_ordinal INTEGER);`,
    );
    history
      .prepare("INSERT INTO thread_turns VALUES(?,?,?,?)")
      .run(id, "turn", "completed", 1);
    history.close();
    const global = path.join(home, ".codex-global-state.json");
    fs.writeFileSync(
      global,
      JSON.stringify({ "electron-persisted-atom-state": {} }),
    );
    const before = fs.readFileSync(global, "utf8");
    const output = execFileSync(
      process.execPath,
      [path.resolve(__dirname, "../../Resources/recent-chats.mjs")],
      {
        encoding: "utf8",
        env: {
          ...process.env,
          CODEX_HOME: home,
          CODEX_BIN: path.join(home, "missing-codex.exe"),
        },
        timeout: 15000,
      },
    );
    const result = JSON.parse(output);
    assert.equal(result.threads.length, 1);
    assert.equal(result.threads[0].title, "Example chat");
    assert.equal(result.threads[0].state, "notified");
    assert.equal(result.threads[0].origin, "Mac");
    assert.equal(fs.readFileSync(global, "utf8"), before);
    assert.equal(fs.existsSync(path.join(home, "auth.json")), false);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});
