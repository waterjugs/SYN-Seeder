// The rules for calling a seed, kept apart from Discord and Cloudflare so the
// tests can check them directly. Times are milliseconds since 1970 (Date.now()).

// These numbers are promised in PRIVACY.md and TERMS.md. Change them there too.
export const LIMITS = Object.freeze({
  // A seed can be called only while the server has fewer players than this.
  maxPlayers: 50,
  // A new call must wait this long after the last one.
  cooldownMs: 30 * 60 * 1000,
  // At most this many calls a day ("today" is the day in DAY_TIME_ZONE).
  callsPerDay: 4,
  // How long PCs act on a call after it's made.
  callLifeMs: 15 * 60 * 1000,
});

// The game server and most of its players are in North America, so "today"
// in the daily limit runs from midnight to midnight US Eastern time.
export const DAY_TIME_ZONE = 'America/New_York';

const dayParts = new Intl.DateTimeFormat('en-US', {
  timeZone: DAY_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
});

// The day ``now`` falls on in DAY_TIME_ZONE, as "2026-11-20".
export function dayOf(now) {
  const parts = Object.fromEntries(dayParts.formatToParts(now).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

// When the day after the one ``now`` falls on begins. Days in DAY_TIME_ZONE
// last 23, 24 or 25 hours, so the start of the next is searched for to the
// millisecond rather than worked out.
export function nextDayStart(now) {
  const today = dayOf(now);
  let before = now;  // still today
  let after = now + 26 * 60 * 60 * 1000;  // certainly a later day
  while (after - before > 1) {
    const middle = Math.floor((before + after) / 2);
    if (dayOf(middle) === today) before = middle;
    else after = middle;
  }
  return after;
}

// What the seed-call flag remembers. Nothing in it is about a person, and
// it's exactly what PRIVACY.md lists.
//   callId:   random ID of the latest call, or null
//   calledAt: when the latest call was made, or null
//   day:      the day of the latest call, as dayOf() writes it, or null
//   count:    how many calls were made that day
export function emptyState() {
  return { callId: null, calledAt: null, day: null, count: 0 };
}

// A stored state, cleaned up so a damaged or old copy can't break the rules.
export function normalState(stored) {
  const state = emptyState();
  if (!stored || typeof stored !== 'object') return state;
  if (typeof stored.callId === 'string' && /^[0-9a-f]{32}$/.test(stored.callId)
      && Number.isFinite(stored.calledAt)) {
    state.callId = stored.callId;
    state.calledAt = stored.calledAt;
  }
  if (typeof stored.day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(stored.day)
      && Number.isInteger(stored.count) && stored.count >= 0) {
    state.day = stored.day;
    state.count = stored.count;
  }
  return state;
}

// How many calls were made on the day ``now`` falls on.
function callsToday(state, now) {
  return state.day === dayOf(now) ? state.count : 0;
}

// Whether a new call is allowed at ``now``.
// Returns { ok: true }, or { ok: false, reason: 'cooldown' | 'daily', retryAt }.
export function checkLimits(state, now) {
  if (state.calledAt !== null && now - state.calledAt < LIMITS.cooldownMs) {
    const cooledAt = state.calledAt + LIMITS.cooldownMs;
    // If the day's calls are used up even then, the real wait is till tomorrow.
    if (callsToday(state, cooledAt) >= LIMITS.callsPerDay) {
      return { ok: false, reason: 'daily', retryAt: nextDayStart(now) };
    }
    return { ok: false, reason: 'cooldown', retryAt: cooledAt };
  }
  if (callsToday(state, now) >= LIMITS.callsPerDay) {
    return { ok: false, reason: 'daily', retryAt: nextDayStart(now) };
  }
  return { ok: true };
}

// The state after a call with ID ``callId`` is made at ``now``.
export function recordCall(state, now, callId) {
  return { callId, calledAt: now, day: dayOf(now), count: callsToday(state, now) + 1 };
}

// The latest call while PCs should still act on it, as { id, calledAt }, or null.
export function liveCall(state, now) {
  if (state.callId === null) return null;
  const age = now - state.calledAt;
  // A call "from the future" can only come from a clock fault; trust it only a little.
  if (age < -60 * 1000 || age >= LIMITS.callLifeMs) return null;
  return { id: state.callId, calledAt: state.calledAt };
}

// What the PCs are sent: the call's ID and its age in whole seconds, or no call.
// The age is worked out here, so a PC's own clock or time zone doesn't matter.
export function seedCallBody(call, now) {
  if (call === null) return { call: null };
  const age = Math.max(0, Math.floor((now - call.calledAt) / 1000));
  if (age * 1000 >= LIMITS.callLifeMs) return { call: null };
  return { call: call.id, age };
}

// A new random call ID: 32 hex characters.
export function newCallId() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
}
