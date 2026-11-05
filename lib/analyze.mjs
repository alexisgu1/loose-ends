// Turns one text thread into "loose ends": specific, still-open reasons to text someone,
// each with the exact quote that triggered it and a draft in your own voice.
//
// Two engines:
//   - Claude (default when an API key is set): reads the thread like a person would.
//   - Offline heuristics: keyword rules, so the app still works with no key. Noticeably dumber.

import Anthropic from "@anthropic-ai/sdk";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";

export const MODEL = "claude-opus-5-5";
const PROMPT_VERSION = "v6";
const DATA_DIR = new URL("../data/", import.meta.url).pathname;
const CACHE_FILE = join(DATA_DIR, "cache.json");

export const LOOP_TYPES = ["event", "reply_owed", "promise", "plan", "drift"];

const SYSTEM = `You help someone who keeps forgetting to follow up with people they care about. Each request is one 1:1 text thread between "Me" (the user) and one other person, plus today's date.

Find the loose ends: things still unresolved today that a thoughtful friend would follow up on. Types:
- event: the other person mentioned something in their life (interview, presentation, trip, move, appointment, exam) that is coming up within about a week or happened in the last few days, and Me hasn't checked in about it since.
- reply_owed: they asked Me something or said something that clearly expects an answer, and Me never replied.
- promise: Me said they would do something (send, call, check, introduce) and nothing later shows it happened.
- plan: someone suggested hanging out or doing something together and it never became a specific day/time.
- drift: no specific loop, but this is clearly someone Me cares about and the thread has gone quiet for 3+ weeks.

Rules:
- Only include loose ends that are still open as of today. If a later message resolves it, skip it.
- "quote" must be copied exactly from one message in the thread.
- Businesses, automated texts, verification codes, and spam: is_personal false, no loose ends.
- A thread where everything was answered and nothing is pending has no loose ends. Don't invent any.
- At most 2 loose ends, most important first. If one text could close two loose ends, mention both in that draft.
- "why" is one short sentence to Me, in second person, plain and specific (e.g. "You said you'd send Priya the referral link and never did.").
- "label" is 2-5 words (e.g. "Climbing never got planned").
- "due_date": for events, the date it happens (YYYY-MM-DD) if you can tell, else null. Otherwise null.

Drafts:
- Write as Me, matching exactly how Me texts this person: casing, punctuation, emoji, slang, and length. Look at Me's lines.
- One text, usually 1-2 short sentences. Reference the actual thing. Use details already in the thread (names, places).
- For a plan, suggest something concrete but easy to say yes to.
- Never mention reminders, apps, or AI. No guilt-trippy apologies. Not cheesy.

closeness: 0 to 1, how close they seem from tone, warmth, and how often they talk.
relationship: one of partner, family, close friend, friend, acquaintance, unknown.`;

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["is_personal", "relationship", "closeness", "loose_ends"],
  properties: {
    is_personal: { type: "boolean" },
    relationship: {
      type: "string",
      enum: ["partner", "family", "close friend", "friend", "acquaintance", "unknown"],
    },
    closeness: { type: "number" },
    loose_ends: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "label", "why", "quote", "quote_from", "quote_date", "due_date", "draft"],
        properties: {
          type: { type: "string", enum: LOOP_TYPES },
          label: { type: "string" },
          why: { type: "string" },
          quote: { type: "string" },
          quote_from: { type: "string", enum: ["me", "them"] },
          quote_date: { type: "string", description: "YYYY-MM-DD of the quoted message" },
          due_date: { anyOf: [{ type: "string" }, { type: "null" }] },
          draft: { type: "string" },
        },
      },
    },
  },
};

// ---------- cache (so re-opening the app is instant and costs nothing) ----------

function loadCache() {
  try {
    return JSON.parse(readFileSync(CACHE_FILE, "utf8"));
  } catch {
    return {};
  }
}
function saveCache(cache) {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2));
}
function cacheKey(thread, engine) {
  const today = fmtDay(new Date().toISOString());
  return createHash("sha1")
    .update(JSON.stringify([PROMPT_VERSION, engine, today, thread.id, thread.messages]))
    .digest("hex");
}

// ---------- shared helpers ----------

// Local dates/times (not UTC), so "last night" and "today" match your clock.
function fmtDay(iso) {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function fmtTime(iso) {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function transcript(thread) {
  return thread.messages
    .map((m) => `[${fmtDay(m.at)} ${fmtTime(m.at)}] ${m.fromMe ? "Me" : thread.name}: ${m.text}`)
    .join("\n");
}

// ---------- Claude engine ----------

let client;
function getClient() {
  if (!client) client = new Anthropic();
  return client;
}

export function hasApiKey() {
  return Boolean(process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN);
}

async function analyzeWithClaude(thread) {
  const today = fmtDay(new Date().toISOString());
  const params = {
    model: MODEL,
    max_tokens: 16000,
    output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
    system: SYSTEM,
    messages: [
      {
        role: "user",
        content: `Today is ${today}.\nThread with ${thread.name}:\n\n${transcript(thread)}`,
      },
    ],
  };

  let response;
  try {
    // Server-side fallback: if a safety classifier declines, the API retries on a
    // fallback model inside the same call instead of failing the whole digest.
    response = await getClient().beta.messages.create({
      ...params,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    });
  } catch (err) {
    if (err instanceof Anthropic.BadRequestError) {
      response = await getClient().messages.create(params);
    } else {
      throw err;
    }
  }

  if (response.stop_reason === "refusal") {
    return { is_personal: false, relationship: "unknown", closeness: 0, loose_ends: [] };
  }
  const text = response.content.find((b) => b.type === "text")?.text;
  if (!text) throw new Error("Empty response from Claude");
  return JSON.parse(text);
}

// ---------- Offline heuristic engine ----------

const RX = {
  promise: /\b(i'?ll|i will|lemme|let me|i'm gonna|im gonna)\s+(send|text|call|check|get back|share|look|introduce|email|venmo)/i,
  plan: /\b(we should|let'?s|lets|we gotta|let me know (if|when) you)\b.*?(sometime|soon|grab|get|hang|climb|dinner|lunch|coffee|catch up|visit|do it|go)\b/i,
  concrete: /\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b|\btomorrow\b|\btonight\b|\b\d{1,2}(:\d\d)?\s?(am|pm)\b|\bat \d/i,
  event: /\b(interview|presentation|exam|final|flight|trip|appointment|surgery|pitch|move|moving|audition|game|recital|birthday)\b/i,
  nonPersonal: /verification code|reply stop|do not share|your code is|unsubscribe/i,
};

function daysSince(iso) {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86400000);
}

function analyzeHeuristic(thread) {
  const msgs = thread.messages;
  const last = msgs.at(-1);
  if (msgs.some((m) => RX.nonPersonal.test(m.text))) {
    return { is_personal: false, relationship: "unknown", closeness: 0, loose_ends: [] };
  }
  const first = thread.name.split(" ")[0];
  const loops = [];
  const after = (i, pred) => msgs.slice(i + 1).some(pred);

  msgs.forEach((m, i) => {
    const age = daysSince(m.at);
    if (m.fromMe && RX.promise.test(m.text) && age <= 21 && !after(i, (n) => n.fromMe && /http|here|sent|done/i.test(n.text))) {
      const what = m.text
        .slice(m.text.search(RX.promise))
        .replace(RX.promise, "$2")
        .replace(/\b(tonight|tomorrow|later|today|asap|soon)\b.*$/i, "")
        .replace(/[.!?\s]+$/, "")
        .replace(/\byou\b/i, "them");
      loops.push({
        type: "promise",
        label: `You said you'd ${what.split(" ").slice(0, 4).join(" ")}`,
        why: `You told ${first} you'd ${what}, and nothing after shows you did.`,
        quote: m.text, quote_from: "me", quote_date: fmtDay(m.at), due_date: null,
        draft: `ok sorry this took forever, here it is!!`,
      });
    }
    if (RX.plan.test(m.text) && age >= 5 && !after(i, (n) => RX.concrete.test(n.text))) {
      loops.push({
        type: "plan",
        label: "Plan never got made",
        why: `You two talked about doing something and never picked a day.`,
        quote: m.text, quote_from: m.fromMe ? "me" : "them", quote_date: fmtDay(m.at), due_date: null,
        draft: `ok we actually need to do this, are you free this weekend?`,
      });
    }
    if (!m.fromMe && RX.event.test(m.text) && !/\?/.test(m.text) && age <= 10 && !after(i, (n) => n.fromMe && /how (did|was)|how'?d/i.test(n.text))) {
      const thing = ["interview","presentation","exam","flight","trip","appointment","surgery","pitch","audition","recital","move","birthday","game","final"].find((w) => new RegExp(`\\b${w}`, "i").test(m.text));
      // Rough date: "tomorrow" or "in N days" relative to when they said it.
      const sent = new Date(m.at);
      let due = null;
      if (/\btomorrow\b/i.test(m.text)) due = new Date(sent.getTime() + 86400000);
      const inN = m.text.match(/\bin (\d+) days?\b/i);
      if (inN) due = new Date(sent.getTime() + Number(inN[1]) * 86400000);
      const upcoming = due && due.getTime() > Date.now() - 12 * 3600000;
      loops.push({
        type: "event",
        label: upcoming ? `${thing[0].toUpperCase()}${thing.slice(1)} coming up` : `How the ${thing} went`,
        why: upcoming
          ? `${first} has ${/^[aeiou]/i.test(thing) ? "an" : "a"} ${thing} coming up. A quick good-luck text goes a long way.`
          : `${first} had ${/^[aeiou]/i.test(thing) ? "an" : "a"} ${thing} recently and you haven't asked how it went.`,
        quote: m.text, quote_from: "them", quote_date: fmtDay(m.at), due_date: due ? fmtDay(due.toISOString()) : null,
        draft: upcoming ? `good luck tomorrow!! you're gonna be so good` : `wait how did the ${thing} go??`,
      });
    }
  });

  if (!last.fromMe && /\?|\byou in\b/i.test(last.text) && daysSince(last.at) >= 0) {
    loops.push({
      type: "reply_owed",
      label: "You never answered",
      why: `${first} asked you something and you haven't replied.`,
      quote: last.text, quote_from: "them", quote_date: fmtDay(last.at), due_date: null,
      draft: `omg sorry just saw this, yes!!`,
    });
  }

  if (!loops.length && daysSince(last.at) >= 21 && msgs.length >= 4) {
    loops.push({
      type: "drift",
      label: "It's been a while",
      why: `You and ${first} haven't talked in ${daysSince(last.at)} days.`,
      quote: msgs.findLast((m) => !m.fromMe)?.text ?? last.text,
      quote_from: "them", quote_date: fmtDay(last.at), due_date: null,
      draft: `hiii i miss you, how's everything going?`,
    });
  }

  const order = (t) => LOOP_TYPES.indexOf(t.type);
  const seen = new Set();
  const unique = loops.filter((l) => !seen.has(l.type) && seen.add(l.type));
  const closeness = Math.min(1, 0.3 + msgs.length / 20);
  return {
    is_personal: true,
    relationship: "unknown",
    closeness,
    loose_ends: unique.sort((a, b) => order(a) - order(b)).slice(0, 2),
  };
}

// ---------- public API ----------

async function pool(items, size, fn) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(size, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        out[i] = await fn(items[i], i);
      }
    })
  );
  return out;
}

export async function analyzeAll(threads, { engine, refresh = false } = {}) {
  const cache = refresh ? {} : loadCache();
  const errors = [];
  const results = await pool(threads, 5, async (thread) => {
    const key = cacheKey(thread, engine);
    if (cache[key]) return { thread, analysis: cache[key] };
    try {
      const analysis = engine === "claude" ? await analyzeWithClaude(thread) : analyzeHeuristic(thread);
      cache[key] = analysis;
      return { thread, analysis };
    } catch (err) {
      errors.push({ name: thread.name, message: err.message });
      return { thread, analysis: analyzeHeuristic(thread), fellBack: true };
    }
  });
  saveCache(cache);
  return { results, errors };
}
