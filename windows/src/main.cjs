"use strict";
const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  ipcMain,
  shell,
  screen,
  nativeImage,
  nativeTheme,
  powerMonitor,
  protocol,
  net,
} = require("electron");
const path = require("node:path"),
  fs = require("node:fs"),
  os = require("node:os");
const { spawn, execFile } = require("node:child_process");
const { pathToFileURL } = require("node:url");
const M = require("./model.cjs");
const demo =
    process.argv.includes("--demo") || process.argv.includes("--desktop-test"),
  desktopTest = process.argv.includes("--desktop-test");
app.setName("notchGPT");
protocol.registerSchemesAsPrivileged([
  {
    scheme: "notchgpt",
    privileges: { standard: true, secure: true, supportFetchAPI: true },
  },
]);
const root = path.join(
  process.env.LOCALAPPDATA || app.getPath("userData"),
  "notchGPT",
);
let prefs = M.preferences(),
  ledger = M.freshLedger(),
  win,
  tray,
  server,
  quotaTimer,
  chatsTimer,
  deadline,
  quotaBusy = false,
  chatsBusy = false,
  pane = "none",
  lastChats = [],
  generation = 0;
let closeTimer = null,
  colorPickerOpen = false;
let state = {
  windows: [],
  percent: null,
  chats: [],
  attention: "none",
  error: "Connecting to Codex…",
  chatError: null,
  updated: null,
};
function read(name) {
  try {
    const file = path.join(root, name);
    if (fs.statSync(file).size > 4 * 1024 * 1024) return null;
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}
function save(name, data) {
  if (demo) return;
  fs.mkdirSync(root, { recursive: true });
  const target = path.join(root, name),
    tmp = target + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(data), { mode: 0o600 });
  fs.renameSync(tmp, target);
}
function resource(name) {
  return app.isPackaged
    ? path.join(process.resourcesPath, name)
    : path.join(__dirname, "../../Resources", name);
}
function findCLI() {
  const override = process.env.CODEX_BIN;
  const candidates = [override];
  for (const dir of (process.env.PATH ?? "").split(path.delimiter))
    if (dir)
      candidates.push(
        path.join(dir, process.platform === "win32" ? "codex.exe" : "codex"),
      );
  if (process.platform === "win32") {
    const bases = [
      path.join(process.env.APPDATA ?? "", "npm/node_modules/@openai"),
      path.join(process.env.ProgramFiles ?? "", "nodejs/node_modules/@openai"),
    ];
    const triple =
      process.arch === "arm64"
        ? "aarch64-pc-windows-msvc"
        : "x86_64-pc-windows-msvc";
    for (const base of bases) {
      candidates.push(
        path.join(base, "codex/vendor", triple, "codex/codex.exe"),
      );
      const arch = process.arch === "arm64" ? "arm64" : "x64";
      candidates.push(
        path.join(
          base,
          `codex-win32-${arch}/vendor`,
          triple,
          "codex/codex.exe",
        ),
      );
      candidates.push(
        path.join(
          base,
          `codex/node_modules/@openai/codex-win32-${arch}/vendor`,
          triple,
          "codex/codex.exe",
        ),
      );
    }
    candidates.push(
      path.join(
        process.env.LOCALAPPDATA ?? "",
        "Programs/Codex/resources/codex.exe",
      ),
    );
  } else
    for (const appPath of [
      "/Applications/Codex.app",
      "/Applications/ChatGPT.app",
      path.join(os.homedir(), "Applications/Codex.app"),
    ])
      candidates.push(
        path.join(
          appPath,
          "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ),
      );
  return candidates.find(
    (p) =>
      p &&
      path.isAbsolute(p) &&
      fs.existsSync(p) &&
      fs.statSync(p).isFile() &&
      !/\.(cmd|bat|ps1)$/i.test(p),
  );
}
function payload() {
  const weekly = state.windows.find((w) => w.duration === 10080 && w.resetsAt);
  return {
    ...state,
    pane,
    preferences: prefs,
    usage: M.viewModel(ledger, weekly),
  };
}
function broadcast() {
  if (win && !win.isDestroyed()) win.webContents.send("state", payload());
}
function resize(next) {
  clearTimeout(closeTimer);
  const closing = next === "none" && pane !== "none" && prefs.animateDropdowns;
  pane = next;
  const area = screen.getPrimaryDisplay().workArea,
    full = screen.getPrimaryDisplay().bounds;
  const width = 360,
    height = next === "none" ? 38 : Math.min(382, area.height);
  const bounds = {
    x: Math.round(full.x + (full.width - width) / 2),
    y: Math.max(full.y, area.y),
    width,
    height,
  };
  if (closing) closeTimer = setTimeout(() => win.setBounds(bounds), 240);
  else win.setBounds(bounds);
  broadcast();
}
function timers() {
  clearInterval(quotaTimer);
  clearInterval(chatsTimer);
  if (demo) return;
  quotaTimer = setInterval(refreshQuota, prefs.usageInterval * 1000);
  chatsTimer = setInterval(
    refreshChats,
    (pane === "chats" ? prefs.chatInterval : Math.max(30, prefs.chatInterval)) *
      1000,
  );
}
function stopServer() {
  generation++;
  clearTimeout(deadline);
  deadline = null;
  quotaBusy = false;
  if (server) {
    server.kill();
    server = null;
  }
}
function refreshQuota() {
  if (demo || quotaBusy) return;
  const cli = findCLI();
  if (!cli) {
    state.error =
      "Codex CLI not found. Install Codex CLI or set CODEX_BIN to codex.exe, then restart.";
    broadcast();
    return;
  }
  quotaBusy = true;
  const id = ++generation;
  let buffer = "",
    initialized = false;
  let proc;
  try {
    proc = spawn(cli, ["app-server"], {
      stdio: ["pipe", "pipe", "ignore"],
      windowsHide: true,
      shell: false,
      cwd: root,
      env: process.env,
    });
  } catch {
    quotaBusy = false;
    state.error = "Could not start Codex.";
    broadcast();
    return;
  }
  server = proc;
  function fail(message) {
    if (id !== generation) return;
    state.error = message;
    stopServer();
    broadcast();
  }
  const send = (data) => {
    if (!proc.stdin.destroyed) proc.stdin.write(JSON.stringify(data) + "\n");
  };
  deadline = setTimeout(
    () => fail("Codex did not respond. Check the existing sign-in and retry."),
    20000,
  );
  proc.once("error", () => fail("Could not start Codex. Check CODEX_BIN."));
  proc.stdin.on("error", () => {});
  proc.once("exit", () => {
    if (id === generation && quotaBusy) fail("Codex usage connection closed.");
  });
  proc.stdout.on("data", (chunk) => {
    if (id !== generation) return;
    buffer += chunk.toString();
    if (buffer.length > 2 * 1024 * 1024) {
      fail("Invalid Codex response.");
      return;
    }
    let end;
    while ((end = buffer.indexOf("\n")) >= 0) {
      let obj;
      try {
        obj = JSON.parse(buffer.slice(0, end));
      } catch {
        buffer = buffer.slice(end + 1);
        continue;
      }
      buffer = buffer.slice(end + 1);
      if (obj.id === 0 && !initialized) {
        if (obj.error) {
          fail("Codex initialization failed.");
          return;
        }
        initialized = true;
        send({ method: "initialized", params: {} });
        send({ id: 1, method: "account/rateLimits/read", params: {} });
      }
      if (obj.id === 1) {
        if (obj.error) {
          fail("Usage unavailable. Sign in through Codex and retry.");
          return;
        }
        const raw =
          obj.result?.rateLimitsByLimitId?.codex ?? obj.result?.rateLimits;
        const windows = M.windows(raw);
        if (!windows.length) {
          fail("No supported quota windows returned.");
          return;
        }
        state.windows = windows;
        state.percent = Math.floor(
          Math.min(...windows.map((w) => w.remaining)),
        );
        state.error = null;
        state.updated = Date.now();
        const weekly = windows.find((w) => w.duration === 10080 && w.resetsAt);
        if (weekly) {
          M.sample(ledger, weekly.used, weekly.resetsAt);
          try {
            save("usage-history.json", ledger);
          } catch {
            state.error = "Usage loaded, but local history could not be saved.";
          }
        }
        stopServer();
        broadcast();
        return;
      }
    }
  });
  send({
    id: 0,
    method: "initialize",
    params: {
      clientInfo: {
        name: "notchgpt-windows",
        title: "notchGPT",
        version: app.getVersion(),
      },
    },
  });
}
function refreshChats() {
  if (demo || chatsBusy) return;
  chatsBusy = true;
  const helper = app.isPackaged
    ? resource("recent-chats.mjs")
    : path.join(__dirname, "../../Resources/recent-chats.mjs");
  const env = {
    ...process.env,
    ELECTRON_RUN_AS_NODE: "1",
    NOTCHGPT_PINNED_CHATS: JSON.stringify(prefs.pinnedChats),
  };
  const cli = findCLI();
  if (cli) env.CODEX_BIN = cli;
  execFile(
    process.execPath,
    [helper],
    {
      env,
      windowsHide: true,
      timeout: 28000,
      maxBuffer: 256 * 1024,
      shell: false,
    },
    (err, stdout) => {
      chatsBusy = false;
      let result;
      try {
        result = JSON.parse(stdout);
      } catch {}
      if (Array.isArray(result?.threads)) {
        lastChats = result.threads;
        state.chats = lastChats;
        state.attention = M.attention(lastChats);
        state.chatError = result.partial
          ? "Some chat sources are unavailable. Remote states were last saved by Codex."
          : null;
      } else state.chatError = "Chats unavailable. Open Codex and retry.";
      broadcast();
    },
  );
}
function trusted(event) {
  return (
    win &&
    !win.isDestroyed() &&
    event.sender === win.webContents &&
    event.senderFrame === win.webContents.mainFrame &&
    event.senderFrame.url.startsWith("notchgpt://app/")
  );
}
function handle(name, fn) {
  ipcMain.handle(name, (event, ...args) => {
    if (!trusted(event)) throw Error("Invalid sender");
    return fn(...args);
  });
}
function installIPC() {
  handle("get-state", () => payload());
  handle("color-picker", (value) => {
    colorPickerOpen = value === true;
  });
  handle("pane", (next) => {
    if (["none", "account", "usage", "chats", "settings"].includes(next)) {
      resize(next);
      timers();
      if (next === "chats") refreshChats();
    }
    return true;
  });
  handle("refresh", () => {
    refreshQuota();
    refreshChats();
  });
  handle("preferences", (raw) => {
    const next = M.preferences(raw);
    if (
      !demo &&
      process.platform === "win32" &&
      next.startAtLogin !== prefs.startAtLogin
    )
      app.setLoginItemSettings({
        openAtLogin: next.startAtLogin,
        path: process.execPath,
      });
    save("preferences.json", next);
    prefs = next;
    timers();
    broadcast();
    return prefs;
  });
  handle("pin", (key) => {
    const chat = lastChats.find((c) => M.pinKey(c) === key);
    if (!chat) return false;
    const pin = {
      id: chat.id,
      hostId: chat.hostId ?? "local",
      kind: chat.kind ?? "codex",
    };
    if (!M.validPin(pin)) return false;
    const index = prefs.pinnedChats.findIndex((p) => M.pinKey(p) === key);
    if (index >= 0) prefs.pinnedChats.splice(index, 1);
    else if (prefs.pinnedChats.length < 10) prefs.pinnedChats.push(pin);
    save("preferences.json", prefs);
    broadcast();
    refreshChats();
    return true;
  });
  handle("reorder", (source, before) => {
    const next = M.movePin(prefs.pinnedChats, source, before);
    if (!next) return false;
    prefs.pinnedChats = next;
    save("preferences.json", prefs);
    broadcast();
    return true;
  });
  handle("open", async (key) => {
    const chat = lastChats.find((c) => M.pinKey(c) === key),
      url = M.linkFor(chat);
    if (!url) return false;
    if (!demo) await shell.openExternal(url);
    resize("none");
    return true;
  });
  handle("quit", () => {
    if (!desktopTest) app.quit();
  });
}
function demoData() {
  const now = Date.now(),
    reset = Math.floor(now / 1000) + 86400 * 2;
  state.windows = M.windows({
    primary: {
      usedPercent: 18,
      windowDurationMins: 300,
      resetsAt: reset - 3600,
    },
    secondary: { usedPercent: 42, windowDurationMins: 10080, resetsAt: reset },
  });
  state.percent = 58;
  state.error = null;
  state.updated = now;
  const day = M.dayKey(new Date());
  ledger.days[day] = {
    samples: 241,
    partial: false,
    bins: Array.from({ length: 16 }, (_, i) => ({
      amount:
        [0.3, 0.75, 0.18, 1.2, 0.54, 0, 0.84, 0.39][i % 8] * (i < 8 ? 1 : 0.8),
      coverage: 1800000,
      estimated: false,
    })),
  };
  const titles = [
    "Add recent chat list",
    "Manage remote host",
    "Check cloud environment",
    "Fix dashboard layout",
    "Update application",
    "Analyze server logs",
    "Prepare weekly report",
    "Check build and tests",
    "Configure environment",
    "Project documentation",
  ];
  lastChats = titles.map((title, i) => ({
    id: "00000000-0000-4000-8000-" + String(i + 1).padStart(12, "0"),
    title,
    state: ["running", "waiting for input", "stopped", "notified"][i % 4],
    origin: ["Windows", "Remote", "Cloud"][i % 3],
    hostId: i % 3 === 1 ? "ssh:example" : "local",
    hostName: i % 3 === 1 ? "example-workstation" : null,
    kind: "codex",
  }));
  state.chats = lastChats;
  state.attention = M.attention(lastChats);
  prefs.pinnedChats = lastChats
    .slice(0, 3)
    .map((c) => ({ id: c.id, kind: c.kind, hostId: c.hostId }));
}
async function desktopChecks() {
  // Synthetic renderer checks run only against the bundled application UI.
  const assert = require("node:assert/strict");
  const out = path.resolve(
    process.env.NOTCHGPT_TEST_OUTPUT ||
      path.join(app.getPath("temp"), "notchgpt-desktop-test"),
  );
  fs.mkdirSync(out, { recursive: true });
  for (const next of ["account", "usage", "chats", "settings", "none"]) {
    resize(next);
    await win.webContents.executeJavaScript(
      `window.notchTestPane(${JSON.stringify(next)})`,
    );
    await new Promise((resolve) => setTimeout(resolve, 350));
    const layout = await win.webContents.executeJavaScript(
      `({width:document.querySelector('#app').getBoundingClientRect().width,height:document.querySelector('#app').getBoundingClientRect().height,rings:[...document.querySelectorAll('.header-button')].map(n=>n.getBoundingClientRect().width),cards:document.querySelectorAll('.chat-card').length,scroll:document.querySelector('#chat-list').scrollHeight>document.querySelector('#chat-list').clientHeight})`,
    );
    assert.equal(layout.width, 360);
    assert.equal(layout.height, next === "none" ? 38 : 382);
    assert.deepEqual(layout.rings, [38, 38, 38, 38]);
    if (next === "chats") {
      assert.equal(layout.cards, 10);
      assert.ok(layout.scroll);
    }
    fs.writeFileSync(
      path.join(out, next + ".png"),
      (await win.webContents.capturePage()).toPNG(),
    );
  }
  const behavior = await win.webContents.executeJavaScript(
    "window.notchRunChecks()",
  );
  assert.equal(behavior, true);
  fs.writeFileSync(
    path.join(out, "result.json"),
    JSON.stringify({
      passed: true,
      platform: process.platform,
      version: app.getVersion(),
      panes: 5,
    }),
  );
  app.exit(0);
}
if (!demo && !app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (win) {
      win.show();
      win.focus();
    }
  });
  app.whenReady().then(async () => {
    if (!demo) {
      prefs = M.preferences(read("preferences.json") ?? {});
      ledger = M.sanitizeLedger(read("usage-history.json"));
      fs.mkdirSync(root, { recursive: true });
    } else demoData();
    protocol.handle("notchgpt", (request) => {
      const url = new URL(request.url);
      const name = decodeURIComponent(url.pathname).slice(1) || "index.html";
      if (
        url.host !== "app" ||
        !["index.html", "style.css", "renderer.js"].includes(name)
      )
        return new Response("Not found", { status: 404 });
      return net.fetch(pathToFileURL(path.join(__dirname, name)).href);
    });
    win = new BrowserWindow({
      width: 360,
      height: 38,
      frame: false,
      transparent: true,
      resizable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      show: false,
      backgroundColor: "#00000000",
      hasShadow: false,
      title: "notchGPT",
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
        webSecurity: true,
        devTools: demo,
      },
    });
    if (process.platform === "win32") {
      try {
        win.setBackgroundMaterial("acrylic");
      } catch {}
    }
    win.webContents.session.setPermissionRequestHandler(
      (_wc, _permission, callback) => callback(false),
    );
    win.webContents.session.setPermissionCheckHandler(() => false);
    win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    win.webContents.on("will-navigate", (event) => event.preventDefault());
    win.on("blur", () => {
      if (!desktopTest && !colorPickerOpen) {
        resize("none");
        win.webContents.send("close-pane");
        timers();
      }
    });
    win.on("close", () => stopServer());
    installIPC();
    await win.loadURL("notchgpt://app/index.html");
    resize("none");
    win.showInactive();
    if (!desktopTest) {
      let icon = nativeImage
        .createFromPath(resource("AppIcon.png"))
        .resize({ width: 20, height: 20 });
      tray = new Tray(icon);
      tray.setToolTip("notchGPT");
      tray.setContextMenu(
        Menu.buildFromTemplate([
          {
            label: "Open recent chats",
            click: () => {
              win.show();
              resize("chats");
              win.focus();
            },
          },
          {
            label: "Refresh",
            click: () => {
              refreshQuota();
              refreshChats();
            },
          },
          {
            label: "Settings",
            click: () => {
              win.show();
              resize("settings");
              win.focus();
            },
          },
          { type: "separator" },
          { label: "Quit", click: () => app.quit() },
        ]),
      );
      tray.on("click", () => {
        win.show();
        resize(pane === "none" ? "chats" : "none");
        win.focus();
      });
    }
    screen.on("display-metrics-changed", () => resize(pane));
    powerMonitor.on("resume", () => {
      refreshQuota();
      refreshChats();
    });
    timers();
    refreshQuota();
    refreshChats();
    if (desktopTest)
      try {
        await desktopChecks();
      } catch (error) {
        console.error(error);
        app.exit(1);
      }
  });
  app.on("before-quit", () => {
    clearInterval(quotaTimer);
    clearInterval(chatsTimer);
    clearTimeout(closeTimer);
    stopServer();
    tray?.destroy();
  });
  app.on("window-all-closed", () => app.quit());
}
