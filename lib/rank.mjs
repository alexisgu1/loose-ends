// Decides who makes tonight's list. Deliberately small: at most 3 people,
// one card per person, so it feels like a nudge and not a guilt list.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const DATA_DIR = new URL("../data/", import.meta.url).pathname;
const STATE_FILE = join(DATA_DIR, "state.json");
export const NIGHTLY_LIMIT = 3;

// How much each kind of loose end matters, before closeness and timing.
const TYPE_WEIGHT = { event: 1.0, reply_owed: 0.95, promise: 0.9, plan: 0.75, drift: 0.6 };
const RELATIONSHIP_BOOST = { partner: 1.15, family: 1.0, "close friend": 1.05, friend: 1.0, acquaintance: 0.85, unknown: 0.95 };

// ---------- state: what you've sent, snoozed, or said "not close" to ----------

export function loadState() {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  } catch {
    return { loops: {}, people: {} };
  }
}
export function saveState(state) {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

const days = (iso) => (Date.now() - new Date(iso).getTime()) / 86400000;

// Timing: time-sensitive things peak near their date; unanswered things get
// more urgent the longer they sit; plans and drift ripen slowly.
function timing(loop, lastAt) {
  const age = days(loop.quote_date + "T12:00:00");
  switch (loop.type) {
    case "event": {
      if (loop.due_date) {
        const until = -days(loop.due_date + "T12:00:00");
        if (until >= -0.5 && until <= 2) return { factor: 1.25, note: "happening very soon" };
        if (until < -0.5 && until >= -4) return { factor: 1.15, note: "just happened" };
        return { factor: 0.8, note: "not for a while" };
      }
      return { factor: age <= 5 ? 1.1 : 0.85, note: `mentioned ${Math.round(age)}d ago` };
    }
    case "reply_owed":
      return { factor: Math.min(1.2, 0.85 + age / 10), note: `waiting ${Math.max(0, Math.round(age))}d` };
    case "promise":
      return { factor: Math.min(1.2, 0.9 + age / 14), note: `promised ${Math.round(age)}d ago` };
    case "plan":
      return { factor: Math.min(1.1, 0.7 + age / 30), note: `${Math.round(age)}d with no plan` };
    default:
      return { factor: Math.min(1.0, 0.6 + days(lastAt) / 60), note: `quiet ${Math.round(days(lastAt))}d` };
  }
}

export function loopId(threadId, loop) {
  return `${threadId}:${loop.type}:${loop.quote_date}:${loop.quote.slice(0, 24)}`;
}

export function rank(results, state) {
  const now = Date.now();
  const candidates = [];
  let snoozed = 0;
  let handled = 0;
  let notClose = 0;

  for (const { thread, analysis } of results) {
    if (!analysis.is_personal || !analysis.loose_ends.length) continue;
    const person = state.people[thread.id];
    if (person?.action === "not_close") {
      notClose++;
      continue;
    }
    if (person?.action === "sent" && days(person.at) < 0.8) {
      handled++;
      continue;
    }
    const lastAt = thread.messages.at(-1).at;
    const open = analysis.loose_ends
      .map((loop) => ({ loop, id: loopId(thread.id, loop) }))
      .filter(({ id }) => {
        const s = state.loops[id];
        if (!s) return true;
        if (s.action === "snooze" && new Date(s.until).getTime() <= now) return true;
        if (s.action === "snooze") snoozed++;
        return false;
      });
    if (!open.length) continue;

    // One card per person: their most important open loose end, plus the rest as context.
    const scored = open.map(({ loop, id }) => {
      const t = timing(loop, lastAt);
      const closeness = Math.max(0, Math.min(1, analysis.closeness));
      const rel = RELATIONSHIP_BOOST[analysis.relationship] ?? 1;
      const score = TYPE_WEIGHT[loop.type] * (0.5 + 0.5 * closeness) * rel * t.factor;
      return {
        id,
        loop,
        score,
        factors: { type: TYPE_WEIGHT[loop.type], closeness, relationship: rel, timing: t.factor, timingNote: t.note },
      };
    });
    scored.sort((a, b) => b.score - a.score);
    const top = scored[0];
    candidates.push({
      id: top.id,
      personId: thread.id,
      name: thread.name,
      handle: thread.handle,
      sample: thread.sample,
      relationship: analysis.relationship,
      lastTalked: lastAt,
      loop: top.loop,
      also: scored.slice(1).map((s) => s.loop),
      score: top.score,
      factors: top.factors,
    });
  }

  candidates.sort((a, b) => b.score - a.score);
  const cards = candidates.slice(0, NIGHTLY_LIMIT);
  return {
    cards,
    overflow: Math.max(0, candidates.length - NIGHTLY_LIMIT),
    snoozed,
    handled,
    notClose,
  };
}

// People you're close to but haven't talked to in a while. Shown when tonight's list is done,
// as an easy "say hi" rather than a loose end.
export const QUIET_DAYS = 7;
export const QUIET_LIMIT = 4;
const FIRST = (name) => name.split(" ")[0];
export function quietPeople(results, state, exclude) {
  const out = [];
  for (const { thread, analysis } of results) {
    if (!analysis.is_personal || exclude.has(thread.id)) continue;
    const person = state.people[thread.id];
    if (person?.action === "not_close") continue;
    if (person?.action === "sent" && days(person.at) < 0.8) continue;
    const closeness = Math.max(0, Math.min(1, analysis.closeness ?? 0));
    if (closeness < 0.45) continue;
    const lastAt = thread.messages.at(-1).at;
    const quiet = days(lastAt);
    if (quiet < QUIET_DAYS) continue;
    const drift = analysis.loose_ends.find((l) => l.type === "drift");
    out.push({
      id: `${thread.id}:quiet`,
      personId: thread.id,
      name: thread.name,
      handle: thread.handle,
      relationship: analysis.relationship,
      lastTalked: lastAt,
      daysQuiet: Math.round(quiet),
      draft: drift?.draft || `hiii it's been a minute!! how've you been`,
      score: closeness * Math.min(1, quiet / 30),
    });
  }
  return out.sort((a, b) => b.score - a.score).slice(0, QUIET_LIMIT);
}
