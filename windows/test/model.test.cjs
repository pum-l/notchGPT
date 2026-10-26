"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  M = require("../src/model.cjs");
const t = (hour, minute = 0, day = "2026-10-26") =>
  new Date(
    day +
      "T" +
      String(hour).padStart(2, "0") +
      ":" +
      String(minute).padStart(2, "0") +
      ":00",
  ).getTime();
const reset = Math.floor(t(9) / 1000) + 7 * 86400;
const pin = (n, hostId = "local") => ({
  id: "00000000-0000-4000-8000-" + String(n).padStart(12, "0"),
  hostId,
  kind: "codex",
});
function near(a, b) {
  assert.ok(Math.abs(a - b) < 1e-7, `${a} != ${b}`);
}
test("preferences reject invalid values, preserve host-aware pins and migrate defaults", () => {
  const p = M.preferences({
    hoverToOpen: "yes",
    quotaColorHex: "red",
    chatInterval: 0,
    textSize: 99,
    pinnedChats: [
      pin(1),
      pin(1),
      pin(1, "ssh:example"),
      { ...pin(2), hostId: "bad\n" },
    ],
  });
  assert.equal(p.hoverToOpen, false);
  assert.equal(p.quotaColorHex, "#B58A1B");
  assert.equal(p.chatInterval, 15);
  assert.equal(p.pinnedChats.length, 2);
  assert.equal(
    M.preferences({ quotaColorHex: "#aabbcc" }).quotaColorHex,
    "#AABBCC",
  );
});
test("safe links allow only chat identities and trusted cloud paths", () => {
  assert.equal(
    M.linkFor({ ...pin(1), hostId: "ssh:pc&other=1" }),
    "codex://threads/" + pin(1).id + "?hostId=ssh%3Apc%26other%3D1",
  );
  assert.equal(M.linkFor({ id: "../../secret", kind: "cloud" }), null);
  assert.equal(
    M.linkFor({ id: "task_test", kind: "cloud", url: "https://evil.example" }),
    "https://chatgpt.com/codex/tasks/task_test",
  );
  assert.equal(M.linkFor({ id: "javascript:alert(1)" }), null);
});
test("all four header attention states remain distinct", () => {
  for (const [states, expected] of [
    [[], "none"],
    [["running", "stopped"], "none"],
    [["waiting for input"], "input"],
    [["notified"], "notified"],
    [["waiting for input", "notified"], "combined"],
  ])
    assert.equal(M.attention(states.map((state) => ({ state }))), expected);
});
test("reordering retains identity, supports both directions and rejects foreign drops", () => {
  const pins = [pin(1), pin(2), pin(3)];
  assert.deepEqual(M.movePin(pins, M.pinKey(pin(3)), M.pinKey(pin(1))), [
    pin(3),
    pin(1),
    pin(2),
  ]);
  assert.deepEqual(M.movePin(pins, M.pinKey(pin(1)), null), [
    pin(2),
    pin(3),
    pin(1),
  ]);
  assert.equal(M.movePin(pins, "unknown", null), null);
  assert.equal(M.movePin(pins, M.pinKey(pin(1)), "unknown"), null);
});
test("quota parsing rejects booleans, nonfinite and out-of-range readings", () => {
  assert.deepEqual(M.windows({ primary: { usedPercent: true } }), []);
  assert.deepEqual(
    M.windows({
      primary: { usedPercent: NaN },
      secondary: { usedPercent: 101 },
    }),
    [],
  );
  assert.equal(
    M.windows({
      primary: { usedPercent: 18, windowDurationMins: 300 },
      secondary: {
        usedPercent: 42,
        windowDurationMins: 10080,
        resetsAt: reset,
      },
    })[1].remaining,
    58,
  );
  assert.equal(M.remaining(20, 3, 42), 85);
  assert.equal(M.remaining(20, 0, 99), 5);
  assert.equal(M.remaining(0, 0, 20), null);
});
test("eight working hours, lunch and weekends match the macOS schedule", () => {
  near(
    M.segments(t(8), t(19)).reduce((a, s) => a + s.end - s.start, 0),
    8 * 3600000,
  );
  assert.equal(M.segments(t(13), t(14)).length, 0);
  assert.equal(
    M.segments(t(9, 0, "2026-10-24"), t(18, 0, "2026-10-24")).length,
    0,
  );
});
test("half-hour bins conserve consumption and distinguish missing from observed zero", () => {
  let l = M.freshLedger();
  M.sample(l, 10, reset, t(9, 29));
  M.sample(l, 12, reset, t(9, 31));
  const bins = l.days["2026-10-26"].bins;
  near(bins[0].amount, 1);
  near(bins[1].amount, 1);
  assert.equal(bins[2], null);
  near(bins[0].coverage, 60000);
  M.sample(l, 12, reset, t(9, 32));
  near(bins[1].amount, 1);
  near(bins[1].coverage, 120000);
  near(M.viewModel(l, { used: 12 }, t(9, 32)).spent, 2);
});
test("corrections, rebound, duplicates and reset timestamp jitter never double charge", () => {
  let l = M.freshLedger();
  for (const [minute, used, r] of [
    [0, 10, reset],
    [1, 12, reset],
    [2, 11, reset],
    [3, 12, reset + 11],
    [4, 13, reset + 11],
  ])
    M.sample(l, used, r, t(10, minute));
  near(M.viewModel(l, { used: 13 }, t(10, 4)).spent, 3);
  M.sample(l, 15, reset, t(10, 4));
  assert.equal(l.previous.used, 13);
  M.sample(l, 14, reset, t(10, 5));
  near(M.viewModel(l, { used: 14 }, t(10, 5)).spent, 4);
});
test("mixed long gaps are excluded, wholly working gaps retain estimated placement", () => {
  let l = M.freshLedger();
  M.sample(l, 10, reset, t(12, 59));
  M.sample(l, 15, reset, t(14, 5));
  near(M.viewModel(l, { used: 15 }, t(14, 5)).spent, 0);
  M.sample(l, 17, reset, t(14, 15));
  const u = M.viewModel(l, { used: 17 }, t(14, 15));
  near(u.spent, 2);
  assert.ok(u.bins[8].estimated);
  near(u.tracked, 600000);
});
test("reset credit is limited to its known post-reset interval", () => {
  const r = Math.floor(t(14) / 1000) + 7 * 86400;
  const previous = { time: t(12, 59), used: 90, reset: r - 7 * 86400 };
  const c = M.credit(previous, 2, r, t(14, 2));
  near(
    c.credits.reduce((a, s) => a + s.amount, 0),
    2,
  );
  near(c.credits[0].start, t(14));
  assert.equal(c.partial, true);
  const instant = M.credit(previous, 1, r, t(14));
  near(instant.credits[0].amount, 1);
});
test("unknown resets are excluded instead of inventing historical use", () => {
  const c = M.credit(
    { time: t(10), used: 90, reset },
    2,
    reset + 7 * 86400,
    t(10, 1),
  );
  assert.deepEqual(c.credits, []);
  assert.ok(c.partial);
});
test("daily remainder and separate four-hour allowance use correct denominators", () => {
  let l = M.freshLedger();
  M.sample(l, 10, reset, t(10));
  M.sample(l, 13, reset, t(10, 1));
  const u = M.viewModel(l, { used: 13 }, t(10, 1));
  assert.equal(u.dailyRemaining, 85);
  assert.equal(u.windowRemaining, 70);
  near(u.spent * 5, 15);
});
test("new days and weekends never borrow previous bars or quota spending", () => {
  let l = M.freshLedger();
  M.sample(l, 10, reset, t(10));
  M.sample(l, 12, reset, t(10, 1));
  const next = M.viewModel(l, { used: 12 }, t(10, 0, "2026-10-27"));
  assert.equal(next.dailyRemaining, null);
  assert.ok(next.bins.every((b) => b === null));
  assert.equal(
    M.viewModel(l, { used: 12 }, t(10, 0, "2026-10-31")).windowRemaining,
    null,
  );
});
test("ledger persistence rejects corrupt values and retains valid bins", () => {
  let l = M.freshLedger();
  M.sample(l, 10, reset, t(10));
  M.sample(l, 11, reset, t(10, 1));
  const restored = M.sanitizeLedger(JSON.parse(JSON.stringify(l)));
  near(M.viewModel(restored, { used: 11 }, t(10, 1)).spent, 1);
  restored.days["2026-10-26"].bins[0] = { amount: -100, coverage: 0 };
  assert.equal(M.sanitizeLedger(restored).days["2026-10-26"].bins[0], null);
});
test("independent minute oracle agrees across opening, lunch, closing and DST week", () => {
  for (const day of ["2026-10-23", "2026-10-26"]) {
    const l = M.freshLedger(),
      r = Math.floor(t(8, 0, day) / 1000) + 7 * 86400;
    let used = 0;
    M.sample(l, used, r, t(8, 0, day));
    let oracle = 0;
    for (let i = 1; i <= 660; i++) {
      used += 0.001;
      const now = t(8, 0, day) + i * 60000;
      M.sample(l, used, r, now);
      const previous = new Date(now - 60000);
      if (
        (previous.getHours() >= 9 && previous.getHours() < 13) ||
        (previous.getHours() >= 14 && previous.getHours() < 18)
      )
        oracle += 0.001;
    }
    near(M.viewModel(l, { used }, t(19, 0, day)).spent, oracle);
    near(oracle, 0.48);
  }
});
