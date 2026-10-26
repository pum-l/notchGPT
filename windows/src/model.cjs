"use strict";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const defaults = Object.freeze({
  hoverToOpen: false,
  animateDropdowns: true,
  usageInterval: 60,
  chatInterval: 15,
  chatCount: 10,
  textSize: 11,
  startAtLogin: false,
  quotaColorHex: "#B58A1B",
  windowColorHex: "#7040A0",
  pinnedChats: [],
});
function pinKey(p) {
  return JSON.stringify([p.kind ?? "codex", p.hostId ?? "local", p.id]);
}
function validPin(p) {
  return (
    p &&
    typeof p.hostId === "string" &&
    p.hostId.length > 0 &&
    p.hostId.length <= 256 &&
    !/[\x00-\x1f\x7f]/.test(p.hostId) &&
    (p.kind === "codex"
      ? UUID.test(p.id)
      : p.kind === "cloud" && /^[A-Za-z0-9_-]+$/.test(p.id))
  );
}
function preferences(raw = {}) {
  const p = { ...defaults };
  for (const k of ["hoverToOpen", "animateDropdowns", "startAtLogin"])
    if (typeof raw[k] === "boolean") p[k] = raw[k];
  for (const [k, values] of Object.entries({
    usageInterval: [30, 60, 120, 300],
    chatInterval: [5, 15, 30, 60],
    chatCount: [5, 10],
    textSize: [10, 11, 12],
  }))
    if (values.includes(raw[k])) p[k] = raw[k];
  for (const k of ["quotaColorHex", "windowColorHex"])
    if (typeof raw[k] === "string" && /^#[0-9a-f]{6}$/i.test(raw[k]))
      p[k] = raw[k].toUpperCase();
  const pins = new Map();
  for (const pin of Array.isArray(raw.pinnedChats) ? raw.pinnedChats : [])
    if (validPin(pin))
      pins.set(pinKey(pin), { id: pin.id, kind: pin.kind, hostId: pin.hostId });
  p.pinnedChats = [...pins.values()].slice(0, 10);
  return p;
}
function movePin(pins, source, before) {
  const a = pins.findIndex((p) => pinKey(p) === source),
    b = before === null ? -1 : pins.findIndex((p) => pinKey(p) === before);
  if (a < 0 || (before !== null && b < 0)) return null;
  if (source === before) return [...pins];
  const result = [...pins],
    [item] = result.splice(a, 1);
  result.splice(
    before === null
      ? result.length
      : result.findIndex((p) => pinKey(p) === before),
    0,
    item,
  );
  return result;
}
function linkFor(chat) {
  if (!chat) return null;
  if (chat.kind === "cloud") {
    if (!/^[A-Za-z0-9_-]+$/.test(chat.id)) return null;
    return "https://chatgpt.com/codex/tasks/" + chat.id;
  }
  if (!UUID.test(chat.id)) return null;
  const pin = { ...chat, kind: "codex", hostId: chat.hostId ?? "local" };
  if (!validPin(pin)) return null;
  return (
    "codex://threads/" +
    chat.id +
    (pin.hostId === "local"
      ? ""
      : "?" + new URLSearchParams({ hostId: pin.hostId }))
  );
}
function attention(chats) {
  const input = chats.some((t) => t.state === "waiting for input"),
    notified = chats.some((t) => t.state === "notified");
  return input
    ? notified
      ? "combined"
      : "input"
    : notified
      ? "notified"
      : "none";
}
function windows(snapshot) {
  return ["primary", "secondary"].flatMap((key) => {
    const w = snapshot?.[key];
    if (
      typeof w?.usedPercent !== "number" ||
      !Number.isFinite(w.usedPercent) ||
      w.usedPercent < 0 ||
      w.usedPercent > 100
    )
      return [];
    const duration =
      Number.isInteger(w.windowDurationMins) && w.windowDurationMins > 0
        ? w.windowDurationMins
        : null;
    const resetsAt =
      Number.isInteger(w.resetsAt) &&
      w.resetsAt > 0 &&
      w.resetsAt < 253402300800
        ? w.resetsAt
        : null;
    return [
      {
        key,
        used: w.usedPercent,
        remaining: 100 - w.usedPercent,
        duration,
        resetsAt,
        title:
          duration === 10080
            ? "Weekly limit"
            : duration && duration % 60 === 0
              ? `${duration / 60}-hour limit`
              : duration
                ? `${duration}-minute limit`
                : "Account limit",
      },
    ];
  });
}
const dayKey = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const weekend = (d) => [0, 6].includes(d.getDay());
function boundary(day, hour) {
  const d = new Date(day + "T00:00:00");
  d.setHours(hour);
  return d.getTime();
}
function segments(start, end) {
  const out = [];
  if (!(end > start)) return out;
  const day = new Date(start);
  day.setHours(0, 0, 0, 0);
  let guard = 0;
  while (day.getTime() < end && guard++ < 370) {
    if (!weekend(day))
      for (const hour of [9, 14]) {
        const key = dayKey(day),
          a = Math.max(start, boundary(key, hour)),
          b = Math.min(end, boundary(key, hour + 4));
        if (b > a) out.push({ day: key, hour, start: a, end: b });
      }
    day.setDate(day.getDate() + 1);
  }
  return out;
}
function remaining(allowance, spent, weekly) {
  return [allowance, spent, weekly].every(Number.isFinite) &&
    allowance > 0 &&
    spent >= 0 &&
    weekly >= 0 &&
    weekly <= 100
    ? Math.min(
        100,
        Math.max(
          0,
          Math.floor(
            (Math.min(Math.max(0, allowance - spent), 100 - weekly) /
              allowance) *
              100 +
              1e-8,
          ),
        ),
      )
    : null;
}
function credit(previous, used, reset, now) {
  if (now <= previous.time) return { credits: [], partial: false };
  const changed = Math.abs(reset - previous.reset) > 60;
  let start = previous.time,
    delta = Math.max(0, used - previous.used);
  if (changed) {
    start = (reset - 7 * 86400) * 1000;
    if (start < previous.time || start > now)
      return { credits: [], partial: true };
    delta = used;
  }
  const spans = segments(start, now),
    duration = now - start,
    work = spans.reduce((sum, s) => sum + s.end - s.start, 0);
  if (duration === 0) {
    const d = new Date(now),
      h = d.getHours(),
      hour = h >= 9 && h < 13 ? 9 : h >= 14 && h < 18 ? 14 : null;
    return {
      credits:
        !weekend(d) && hour !== null
          ? [{ day: dayKey(d), hour, start: now, end: now, amount: delta }]
          : [],
      partial: changed,
    };
  }
  if (work > 0 && duration > 180000 && Math.abs(work - duration) >= 1)
    return { credits: [], partial: true };
  return {
    credits: spans.map((s) => ({
      ...s,
      amount: (delta * (s.end - s.start)) / duration,
    })),
    partial: changed,
  };
}
function freshLedger() {
  return { version: 1, previous: null, days: {} };
}
function sanitizeLedger(raw) {
  if (raw?.version !== 1 || !raw.days || typeof raw.days !== "object")
    return freshLedger();
  const result = freshLedger(),
    p = raw.previous;
  if (
    p &&
    [p.time, p.used, p.reset].every(Number.isFinite) &&
    p.used >= 0 &&
    p.used <= 100 &&
    p.reset > 0
  )
    result.previous = p;
  for (const [key, d] of Object.entries(raw.days).slice(-14))
    if (
      /^\d{4}-\d{2}-\d{2}$/.test(key) &&
      d &&
      Array.isArray(d.bins) &&
      d.bins.length === 16
    ) {
      const bins = d.bins.map((b) =>
        b &&
        Number.isFinite(b.amount) &&
        b.amount >= 0 &&
        Number.isFinite(b.coverage) &&
        b.coverage >= 0 &&
        b.coverage <= 1800000
          ? { amount: b.amount, coverage: b.coverage, estimated: !!b.estimated }
          : null,
      );
      result.days[key] = {
        bins,
        samples: Number.isInteger(d.samples) && d.samples >= 0 ? d.samples : 0,
        partial: !!d.partial,
      };
    }
  return result;
}
function sample(ledger, used, reset, time = Date.now()) {
  if (
    !Number.isFinite(used) ||
    used < 0 ||
    used > 100 ||
    !Number.isInteger(reset) ||
    reset <= 0
  )
    return ledger;
  if (ledger.previous && time <= ledger.previous.time) return ledger;
  const key = dayKey(new Date(time));
  ledger.days[key] ??= {
    bins: Array(16).fill(null),
    samples: 0,
    partial: true,
  };
  const current = ledger.days[key];
  current.samples++;
  if (ledger.previous) {
    const attributed = credit(ledger.previous, used, reset, time);
    current.partial ||= attributed.partial;
    for (const s of attributed.credits) {
      ledger.days[s.day] ??= {
        bins: Array(16).fill(null),
        samples: 0,
        partial: true,
      };
      const d = ledger.days[s.day],
        opening = boundary(s.day, s.hour),
        duration = s.end - s.start;
      if (duration === 0) {
        const index =
          (s.hour === 14 ? 8 : 0) + Math.floor((s.end - opening) / 1800000);
        if (index >= 0 && index < 16) {
          d.bins[index] ??= { amount: 0, coverage: 0, estimated: false };
          d.bins[index].amount += s.amount;
        }
        continue;
      }
      for (let i = 0; i < 8; i++) {
        const overlap = Math.max(
          0,
          Math.min(s.end, opening + (i + 1) * 1800000) -
            Math.max(s.start, opening + i * 1800000),
        );
        if (!overlap) continue;
        const index = (s.hour === 14 ? 8 : 0) + i;
        d.bins[index] ??= { amount: 0, coverage: 0, estimated: false };
        d.bins[index].amount += (s.amount * overlap) / duration;
        d.bins[index].coverage += overlap;
        d.bins[index].estimated ||= duration > 180000;
      }
    }
  }
  const same = ledger.previous && Math.abs(ledger.previous.reset - reset) <= 60;
  ledger.previous = {
    time,
    used: same ? Math.max(used, ledger.previous.used) : used,
    reset,
  };
  for (const day of Object.keys(ledger.days).sort().slice(0, -14))
    delete ledger.days[day];
  return ledger;
}
function viewModel(ledger, quota, time = Date.now()) {
  const date = new Date(time),
    key = dayKey(date),
    day = ledger.days[key],
    bins = day?.bins ?? Array(16).fill(null),
    hour = date.getHours();
  let active = hour >= 14 ? 14 : 9;
  if (hour < 9 || weekend(date) || !day) active = null;
  const selected =
      active === null
        ? []
        : bins.slice(active === 9 ? 0 : 8, active === 9 ? 8 : 16),
    spent = bins.reduce((s, b) => s + (b?.amount ?? 0), 0),
    windowSpent = selected.reduce((s, b) => s + (b?.amount ?? 0), 0),
    covered = selected.reduce((s, b) => s + (b?.coverage ?? 0), 0);
  const observed = selected.some(Boolean),
    weekly = quota?.used;
  const pace = covered > 0 ? windowSpent / (covered / 3600000) : null;
  const closing = active === null ? time : boundary(key, active + 4),
    forecast = observed
      ? windowSpent + ((pace ?? 0) * Math.max(0, closing - time)) / 3600000
      : null;
  return {
    day: key,
    bins,
    spent,
    windowSpent,
    tracked: bins.reduce((s, b) => s + (b?.coverage ?? 0), 0),
    windowRemaining:
      observed && quota ? remaining(10, windowSpent, weekly) : null,
    dailyRemaining:
      day && quota && !weekend(date) ? remaining(20, spent, weekly) : null,
    pace,
    forecast:
      quota && forecast !== null
        ? Math.min(forecast, windowSpent + 100 - weekly)
        : null,
    samples: day?.samples ?? 0,
    active,
    partial: day?.partial ?? true,
  };
}
module.exports = {
  defaults,
  preferences,
  pinKey,
  validPin,
  movePin,
  linkFor,
  attention,
  windows,
  dayKey,
  boundary,
  segments,
  remaining,
  credit,
  freshLedger,
  sanitizeLedger,
  sample,
  viewModel,
};
