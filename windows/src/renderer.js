"use strict";
const $ = (selector) => document.querySelector(selector);
const key = (c) =>
  JSON.stringify([c.kind ?? "codex", c.hostId ?? "local", c.id]);
const api = window.notch;
let current,
  selected = "none",
  dragging = null,
  pending = null,
  hoverTimer = null,
  suppressed = null,
  holdUpdates = false;
const pct = (v) => (v === null || v === undefined ? "—" : String(v));
function node(tag, className, text) {
  const n = document.createElement(tag);
  if (className) n.className = className;
  if (text !== undefined) n.textContent = text;
  return n;
}
function switchPane(next, notify = true) {
  if (!["none", "account", "usage", "chats", "settings"].includes(next)) return;
  selected = next;
  $("#app").classList.toggle("closed", next === "none");
  for (const name of ["account", "usage", "chats", "settings"]) {
    $("#" + name + "-pane").hidden = next !== name;
    $("#" + name + "-button").classList.toggle("selected", next === name);
  }
  if (notify) api?.pane(next);
  if (next === "usage" && current) drawChart(current.usage);
}
function activate(pane) {
  suppressed = pane;
  clearTimeout(hoverTimer);
  switchPane(selected === pane ? "none" : pane);
}
for (const pane of ["account", "usage", "chats", "settings"]) {
  const button = $("#" + pane + "-button");
  button.onclick = () => activate(pane);
  button.onmouseenter = () => {
    if (current?.preferences.hoverToOpen && suppressed !== pane && !dragging)
      hoverTimer = setTimeout(() => switchPane(pane), 300);
  };
  button.onmouseleave = () => {
    clearTimeout(hoverTimer);
    suppressed = null;
  };
}
for (const button of document.querySelectorAll(".close"))
  button.onclick = () => switchPane("none");
for (const button of document.querySelectorAll(".refresh"))
  button.onclick = () => api?.refresh();
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    clearTimeout(hoverTimer);
    if (dragging) {
      dragging = null;
      renderChats(current);
    } else switchPane("none");
  }
});
document.addEventListener("contextmenu", (event) => {
  event.preventDefault();
  switchPane("settings");
});
function dial(id, value) {
  $("#" + (id === "quota" ? "account" : "usage") + "-button").classList.toggle(
    "unavailable",
    value === null || value === undefined,
  );
  $("#" + id + "-number").replaceChildren(
    document.createTextNode(pct(value)),
    node("small", "", "%"),
  );
  $(
    "#" + (id === "quota" ? "quota" : "window") + "-progress",
  ).style.strokeDashoffset = String(87.9646 * (1 - (value ?? 0) / 100));
}
function render(data) {
  if (dragging || holdUpdates) {
    pending = data;
    return;
  }
  current = data;
  if (data.pane !== undefined && data.pane !== selected)
    switchPane(data.pane, false);
  const p = data.preferences;
  document.documentElement.style.setProperty("--quota", p.quotaColorHex);
  document.documentElement.style.setProperty("--window", p.windowColorHex);
  document.documentElement.style.setProperty("--text-size", p.textSize + "px");
  document.documentElement.style.setProperty(
    "--scale",
    String(p.textSize / 11),
  );
  $("#app").classList.toggle("no-motion", !p.animateDropdowns);
  dial("quota", data.percent);
  dial("window", data.usage.windowRemaining);
  const alert = $("#chats-button");
  alert.className =
    "header-button icon-button attention-" +
    data.attention +
    (selected === "chats" ? " selected" : "");
  alert.setAttribute(
    "aria-label",
    "Recent chats" +
      ({
        none: "",
        input: " — waiting for input",
        notified: " — notified",
        combined: " — waiting for input and notified",
      }[data.attention] ?? ""),
  );
  alert.title = alert.getAttribute("aria-label");
  renderAccount(data);
  renderUsage(data);
  renderChats(data);
  for (const [name, value] of Object.entries(p)) {
    const control = document.getElementById(name);
    if (!control) continue;
    if (control.type === "checkbox") control.checked = value;
    else control.value = String(value);
  }
}
function renderAccount(data) {
  const area = $("#account-windows");
  area.replaceChildren();
  for (const w of data.windows) {
    const card = node("div", "quota-card"),
      title = node("div", "quota-title");
    title.append(
      node("span", "", w.title),
      node("span", "value", Math.floor(w.remaining) + "%"),
    );
    card.append(
      title,
      node(
        "p",
        "caption",
        w.used.toFixed(1) +
          "% used · " +
          w.remaining.toFixed(1) +
          "% remaining",
      ),
    );
    const bar = node("div", "bar"),
      fill = node("i");
    fill.style.width = w.remaining + "%";
    bar.append(fill);
    card.append(
      bar,
      node(
        "p",
        "caption",
        w.resetsAt
          ? "Resets " + new Date(w.resetsAt * 1000).toLocaleString()
          : "Reset time unavailable",
      ),
    );
    area.append(card);
  }
  $("#account-updated").textContent = data.updated
    ? "Updated " + new Date(data.updated).toLocaleTimeString()
    : "Waiting for quota data";
  $("#quota-error").textContent = data.error ?? "";
}
function renderUsage(data) {
  const u = data.usage,
    fmt = (v) => (v === null || v === undefined ? "—" : v.toFixed(1)),
    hours = u.tracked / 3600000;
  const columns = [
    [
      ["Window", u.active === null ? "—" : u.active === 9 ? "09–13" : "14–18"],
      ["Pace/h", fmt(u.pace) + " pp"],
      ["Forecast", fmt(u.forecast) + " pp"],
    ],
    [
      ["Win. left", pct(u.windowRemaining) + "%"],
      ["Win. used", fmt(u.windowSpent * 10) + "%"],
      ["Samples", String(u.samples)],
    ],
    [
      ["Day used", fmt(u.spent * 5) + "%"],
      ["Day left", pct(u.dailyRemaining) + "%"],
      [
        "Tracked",
        Math.floor(hours) + "h " + Math.floor((hours % 1) * 60) + "m",
      ],
    ],
  ];
  const area = $("#usage-stats");
  area.replaceChildren();
  for (const values of columns) {
    const col = node("div", "stat-column");
    for (const [label, value] of values) {
      const row = node("div", "stat");
      row.append(node("span", "", label), node("b", "", value));
      col.append(row);
    }
    area.append(col);
  }
  $("#chart-date").textContent = new Date(
    u.day + "T12:00:00",
  ).toLocaleDateString(undefined, {
    weekday: "short",
    day: "numeric",
    month: "short",
  });
  drawChart(u);
}
function svg(tag, attributes, text) {
  const n = document.createElementNS("http://www.w3.org/2000/svg", tag);
  for (const [k, v] of Object.entries(attributes)) n.setAttribute(k, String(v));
  if (text !== undefined) n.textContent = text;
  return n;
}
function drawChart(u) {
  const chart = $("#chart");
  chart.replaceChildren();
  const bins = u.bins,
    max = Math.max(1.5, ...bins.map((b) => b?.amount ?? 0)),
    top = 22,
    bottom = 160;
  const defs = svg("defs", {}),
    pattern = svg("pattern", {
      id: "hatch",
      width: 4,
      height: 4,
      patternUnits: "userSpaceOnUse",
    });
  pattern.append(
    svg("path", {
      d: "M-1 1L1 -1M0 4L4 0M3 5L5 3",
      stroke: "#ffffff70",
      "stroke-width": 1,
    }),
  );
  defs.append(pattern);
  chart.append(defs);
  for (const [title, x] of [
    ["09:00–13:00", 95],
    ["14:00–18:00", 257],
  ])
    chart.append(
      svg(
        "text",
        { x, y: 12, "text-anchor": "middle", fill: "#aaa", "font-size": 9 },
        title,
      ),
    );
  for (const ratio of [0, 0.5, 1]) {
    const y = bottom - (bottom - top) * ratio;
    chart.append(
      svg("line", {
        x1: 24,
        y1: y,
        x2: 334,
        y2: y,
        stroke: "#ffffff0c",
        "stroke-width": 0.6,
      }),
      svg(
        "text",
        { x: 18, y: y + 3, "text-anchor": "end", fill: "#888", "font-size": 8 },
        ratio === 0 ? "0" : (max * ratio).toFixed(2),
      ),
    );
  }
  bins.forEach((b, i) => {
    const x = 27 + i * 17.5 + (i >= 8 ? 23 : 0),
      height = b ? Math.max(1.5, (b.amount / max) * (bottom - top)) : 0,
      rect = svg("rect", {
        x,
        y: bottom - height,
        width: 12,
        height: height || 1.5,
        rx: 1.5,
        fill: b ? "var(--window)" : "#ffffff16",
      });
    const hour = (i < 8 ? 9 : 14) + Math.floor((i % 8) / 2),
      start = String(hour).padStart(2, "0") + ":" + (i % 2 ? "30" : "00"),
      end =
        String(hour + (i % 2 ? 1 : 0)).padStart(2, "0") +
        ":" +
        (i % 2 ? "00" : "30");
    rect.append(
      svg(
        "title",
        {},
        start +
          "–" +
          end +
          ": " +
          (b
            ? b.amount.toFixed(2) +
              " pp" +
              (b.estimated || b.coverage < 1800000
                ? " · partial / estimated"
                : "")
            : "No data"),
      ),
    );
    chart.append(rect);
    if (b && (b.estimated || b.coverage < 1800000))
      chart.append(
        svg("rect", {
          x,
          y: bottom - height,
          width: 12,
          height,
          fill: "url(#hatch)",
          "pointer-events": "none",
        }),
      );
  });
  for (const [text, x] of [
    ["09", 27],
    ["11", 97],
    ["13", 162],
    ["14", 190],
    ["16", 249],
    ["18", 331],
  ])
    chart.append(
      svg(
        "text",
        { x, y: 175, fill: "#999", "font-size": 8, "text-anchor": "middle" },
        text,
      ),
    );
}
function renderChats(data) {
  if (!data) return;
  const list = $("#chat-list"),
    scroll = list.scrollTop;
  list.replaceChildren();
  const pins = data.preferences.pinnedChats,
    ranks = new Map(pins.map((p, i) => [key(p), i]));
  const chats = [...data.chats]
    .sort((a, b) => (ranks.get(key(a)) ?? 100) - (ranks.get(key(b)) ?? 100))
    .slice(0, data.preferences.chatCount);
  $("#chat-caption").textContent =
    pins.length +
    " pinned · " +
    chats.length +
    " recent · refresh every " +
    data.preferences.chatInterval +
    " s";
  $("#chat-error").textContent = data.chatError ?? "";
  list.style.height = data.chatError ? "260px" : "280px";
  for (const chat of chats) {
    const id = key(chat),
      pinned = ranks.has(id),
      card = node("div", "chat-card");
    card.dataset.key = id;
    const link = node("button", "chat-link");
    link.setAttribute(
      "aria-label",
      chat.title + " · " + (chat.state ?? "Unavailable"),
    );
    link.title = chat.title;
    link.append(node("span", "chat-title", chat.title));
    const state = chat.state ?? "unavailable",
      status = node(
        "span",
        "chat-status " +
          ({
            running: "state-running",
            "waiting for input": "state-input",
            notified: "state-notified",
          }[state] ?? "state-stopped"),
      );
    if (state === "running") status.append(node("span", "spin", "◌"));
    else if (state === "notified") {
      const bell = svg("svg", {
        viewBox: "0 0 12 12",
        width: 9,
        height: 9,
        fill: "currentColor",
      });
      bell.append(
        svg("path", {
          d: "M6 1a3 3 0 0 0-3 3v3L2 9h8L9 7V4a3 3 0 0 0-3-3M5 10h2v1H5z",
        }),
      );
      status.append(bell, document.createTextNode(" "));
    } else status.append(document.createTextNode("● "));
    status.append(
      document.createTextNode(
        state === "waiting for input"
          ? "Waiting for input"
          : state[0].toUpperCase() + state.slice(1),
      ),
    );
    link.append(status);
    link.onclick = () => {
      if (!dragging) api?.open(id);
    };
    const handle = node("button", "drag-handle", pinned ? "⠿" : "");
    handle.setAttribute("aria-label", "Reorder pinned chat: " + chat.title);
    handle.disabled = !pinned;
    handle.draggable = pinned;
    handle.ondragstart = (event) => {
      dragging = id;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", id);
      card.classList.add("dragging");
    };
    handle.ondragend = () => endDrag();
    handle.onkeydown = (event) => {
      if (event.altKey && ["ArrowUp", "ArrowDown"].includes(event.key)) {
        event.preventDefault();
        const index = pins.findIndex((p) => key(p) === id);
        const target =
          event.key === "ArrowUp" ? pins[index - 1] : pins[index + 2];
        if (event.key === "ArrowUp" && !target) return;
        api?.reorder(id, target ? key(target) : null);
      }
    };
    card.ondragover = (event) => {
      if (dragging && pinned) {
        event.preventDefault();
        document
          .querySelectorAll(".drop-before")
          .forEach((n) => n.classList.remove("drop-before"));
        card.classList.add("drop-before");
      }
    };
    card.ondrop = (event) => {
      event.preventDefault();
      if (dragging && pinned) {
        api?.reorder(dragging, id);
        endDrag();
      }
    };
    const pin = node("button", "pin" + (pinned ? " pinned" : ""));
    const pinIcon = svg("svg", {
      viewBox: "0 0 16 16",
      width: 14,
      height: 14,
      fill: pinned ? "currentColor" : "none",
      stroke: "currentColor",
      "stroke-width": 1.1,
    });
    pinIcon.append(
      svg("path", { d: "M5 2h6l-1 5 2 2v1H9v4L8 15l-1-5H4V9l2-2z" }),
    );
    pin.append(pinIcon);
    pin.setAttribute("aria-label", (pinned ? "Unpin " : "Pin ") + chat.title);
    pin.title = pin.getAttribute("aria-label");
    pin.onclick = () => api?.pin(id);
    let location =
      chat.origin === "Remote"
        ? chat.hostName || chat.hostId || "Remote computer"
        : chat.hostId === "local" && chat.origin === "Mac"
          ? "Windows"
          : chat.origin;
    const badge = node(
      "span",
      "location",
      (chat.origin === "Remote"
        ? "▣ "
        : chat.origin === "Cloud"
          ? "☁ "
          : "▰ ") + location,
    );
    badge.title = location;
    card.append(link, handle, pin, badge);
    list.append(card);
  }
  list.scrollTop = scroll;
}
function endDrag() {
  dragging = null;
  document
    .querySelectorAll(".drop-before,.dragging")
    .forEach((n) => n.classList.remove("drop-before", "dragging"));
  if (pending) {
    const data = pending;
    pending = null;
    render(data);
  } else renderChats(current);
}
$("#chat-list").ondragover = (event) => {
  if (!dragging) return;
  event.preventDefault();
  const list = $("#chat-list"),
    bounds = list.getBoundingClientRect();
  if (event.clientY < bounds.top + 24) list.scrollTop -= 10;
  if (event.clientY > bounds.bottom - 24) list.scrollTop += 10;
};
$("#chat-list").ondrop = (event) => {
  if (event.target === $("#chat-list") && dragging) {
    event.preventDefault();
    api?.reorder(dragging, null);
    endDrag();
  }
};
for (const name of [
  "hoverToOpen",
  "animateDropdowns",
  "usageInterval",
  "chatInterval",
  "chatCount",
  "textSize",
  "startAtLogin",
  "quotaColorHex",
  "windowColorHex",
]) {
  const control = document.getElementById(name);
  control.onchange = () => {
    if (!current) return;
    const p = { ...current.preferences };
    p[name] =
      control.type === "checkbox"
        ? control.checked
        : control.type === "color"
          ? control.value
          : Number(control.value);
    api?.preferences(p);
  };
}
$("#restore").onclick = () =>
  api?.preferences({
    startAtLogin: current?.preferences.startAtLogin ?? false,
  });
window.notchTestPane = (next) => switchPane(next, false);
window.notchRunChecks = async () => {
  if (!current || current.chats.length !== 10) return false;
  const input = $("#hoverToOpen");
  if (input.checked) return false;
  switchPane("chats", false);
  const first = $(".chat-title");
  if (first.textContent !== "Add recent chat list") return false;
  const before = $("#chat-list").scrollTop;
  $("#chat-list").scrollTop = 100;
  if ($("#chat-list").scrollTop <= before) return false;
  const firstKey = key(current.preferences.pinnedChats[0]),
    extra = key(current.chats[3]);
  await api.pin(extra);
  let result = await api.getState();
  if (result.preferences.pinnedChats.length !== 4) return false;
  await api.reorder(firstKey, null);
  result = await api.getState();
  if (key(result.preferences.pinnedChats.at(-1)) !== firstKey) return false;
  await api.pin(extra);
  result = await api.getState();
  if (result.preferences.pinnedChats.length !== 3) return false;
  if ((await api.open("untrusted")) !== false) return false;
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  return selected === "none" && $("#app").classList.contains("closed");
};
for (const name of ["quotaColorHex", "windowColorHex"]) {
  const input = document.getElementById(name);
  input.addEventListener("pointerdown", () => api?.colorPicker(true));
  input.addEventListener("change", () => api?.colorPicker(false));
  input.addEventListener("blur", () => api?.colorPicker(false));
}
if (api) {
  api.onClose(() => switchPane("none", false));
  api.subscribe(render);
  api.getState().then(render);
} else {
  document.body.textContent = "Open notchGPT using the packaged desktop app.";
}
