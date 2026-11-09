import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DAY_TIME_ZONE, LIMITS, checkLimits, dayOf, emptyState, liveCall, newCallId, nextDayStart, normalState, recordCall, seedCallBody,
} from '../src/rules.js';
import { HOUR, MINUTE } from './helpers.js';

// 20 November 2026, 7:00 am US Eastern (EST, 5 hours behind UTC).
const T0 = Date.UTC(2026, 10, 20, 12, 0, 0);
const ID = '0123456789abcdef0123456789abcdef';

test('the limits match what PRIVACY.md and TERMS.md promise', () => {
  assert.equal(LIMITS.maxPlayers, 50);
  assert.equal(LIMITS.cooldownMs, 30 * MINUTE);
  assert.equal(LIMITS.callsPerDay, 4);
  assert.equal(LIMITS.callLifeMs, 15 * MINUTE);
  assert.equal(DAY_TIME_ZONE, 'America/New_York');
});

test('a first call is allowed', () => {
  assert.deepEqual(checkLimits(emptyState(), T0), { ok: true });
});

test('a call within 30 minutes of the last one is refused until the 30 minutes are up', () => {
  const state = recordCall(emptyState(), T0, ID);
  assert.deepEqual(checkLimits(state, T0 + 29 * MINUTE), { ok: false, reason: 'cooldown', retryAt: T0 + 30 * MINUTE });
  assert.deepEqual(checkLimits(state, T0 + 30 * MINUTE), { ok: true });
});

test('a fifth call on the same day is refused until midnight US Eastern', () => {
  let state = emptyState();
  for (let i = 0; i < 4; i++) state = recordCall(state, T0 + i * HOUR, newCallId());
  assert.equal(state.count, 4);
  const midnight = Date.UTC(2026, 10, 21, 5, 0, 0);
  assert.deepEqual(checkLimits(state, T0 + 4 * HOUR), { ok: false, reason: 'daily', retryAt: midnight });
  assert.deepEqual(checkLimits(state, midnight - 1), { ok: false, reason: 'daily', retryAt: midnight });
  assert.deepEqual(checkLimits(state, midnight), { ok: true });
});

test('straight after the day\'s 4th call, the wait given is till midnight, not 30 minutes', () => {
  let state = emptyState();
  for (let i = 0; i < 4; i++) state = recordCall(state, T0 + i * HOUR, newCallId());
  const midnight = Date.UTC(2026, 10, 21, 5, 0, 0);
  assert.deepEqual(checkLimits(state, T0 + 3 * HOUR + 10 * MINUTE), { ok: false, reason: 'daily', retryAt: midnight });
});

test('a 4th call just before midnight leaves a normal 30-minute wait into the new day', () => {
  let state = emptyState();
  const lateEvening = Date.UTC(2026, 10, 21, 4, 45, 0);  // 11:45 pm US Eastern
  for (let i = 3; i >= 0; i--) state = recordCall(state, lateEvening - i * HOUR, newCallId());
  assert.equal(state.count, 4);
  assert.deepEqual(checkLimits(state, lateEvening + 5 * MINUTE), { ok: false, reason: 'cooldown', retryAt: lateEvening + 30 * MINUTE });
  assert.deepEqual(checkLimits(state, lateEvening + 30 * MINUTE), { ok: true });
});

test('the count starts again on a new day', () => {
  let state = emptyState();
  for (let i = 0; i < 4; i++) state = recordCall(state, T0 + i * HOUR, newCallId());
  state = recordCall(state, Date.UTC(2026, 10, 21, 5, 0, 0), ID);
  assert.deepEqual(state, { callId: ID, calledAt: Date.UTC(2026, 10, 21, 5, 0, 0), day: '2026-11-21', count: 1 });
});

test('the flag keeps only the latest call, when it was made, and how many were made that day', () => {
  let state = emptyState();
  for (let i = 0; i < 3; i++) state = recordCall(state, T0 + i * HOUR, newCallId());
  state = recordCall(state, T0 + 3 * HOUR, ID);
  assert.deepEqual(state, { callId: ID, calledAt: T0 + 3 * HOUR, day: '2026-11-20', count: 4 });
});

test('days are US Eastern days, summer time included', () => {
  assert.equal(dayOf(Date.UTC(2026, 10, 21, 4, 59, 59, 999)), '2026-11-20');
  assert.equal(dayOf(Date.UTC(2026, 10, 21, 5, 0, 0)), '2026-11-21');
  assert.equal(dayOf(Date.UTC(2027, 6, 4, 3, 59, 59, 999)), '2027-07-03');
  assert.equal(dayOf(Date.UTC(2027, 6, 4, 4, 0, 0)), '2027-07-04');
});

test('the next day starts at midnight US Eastern, on 23- and 25-hour days too', () => {
  assert.equal(nextDayStart(T0), Date.UTC(2026, 10, 21, 5, 0, 0));
  assert.equal(nextDayStart(Date.UTC(2026, 10, 21, 4, 59, 59, 999)), Date.UTC(2026, 10, 21, 5, 0, 0));
  assert.equal(nextDayStart(Date.UTC(2026, 10, 21, 5, 0, 0)), Date.UTC(2026, 10, 22, 5, 0, 0));
  // Clocks go back on 1 November 2026: that day has 25 hours.
  assert.equal(nextDayStart(Date.UTC(2026, 10, 1, 4, 30, 0)), Date.UTC(2026, 10, 2, 5, 0, 0));
  // Clocks go forward on 14 March 2027: that day has 23 hours.
  assert.equal(nextDayStart(Date.UTC(2027, 2, 14, 5, 30, 0)), Date.UTC(2027, 2, 15, 4, 0, 0));
  assert.equal(nextDayStart(Date.UTC(2027, 6, 4, 12, 0, 0)), Date.UTC(2027, 6, 5, 4, 0, 0));
});

test('a call is live for 15 minutes', () => {
  const state = recordCall(emptyState(), T0, ID);
  assert.deepEqual(liveCall(state, T0), { id: ID, calledAt: T0 });
  assert.deepEqual(liveCall(state, T0 + 15 * MINUTE - 1), { id: ID, calledAt: T0 });
  assert.equal(liveCall(state, T0 + 15 * MINUTE), null);
  assert.equal(liveCall(emptyState(), T0), null);
});

test('a call far in the future, from a clock fault, is ignored', () => {
  const state = recordCall(emptyState(), T0 + 2 * MINUTE, ID);
  assert.equal(liveCall(state, T0), null);
  assert.notEqual(liveCall(recordCall(emptyState(), T0 + 30 * 1000, ID), T0), null);
});

test('the PCs get the call ID and its age in whole seconds', () => {
  const call = { id: ID, calledAt: T0 };
  assert.deepEqual(seedCallBody(call, T0 + 61_999), { call: ID, age: 61 });
  assert.deepEqual(seedCallBody(call, T0 - 5000), { call: ID, age: 0 });
  assert.deepEqual(seedCallBody(call, T0 + 15 * MINUTE), { call: null });
  assert.deepEqual(seedCallBody(null, T0), { call: null });
});

test('the PCs get a body small enough for the app to read strictly', () => {
  const text = JSON.stringify(seedCallBody({ id: ID, calledAt: T0 }, T0 + 899_000));
  assert.equal(text, `{"call":"${ID}","age":899}`);
  assert.ok(text.length <= 512);
});

test('call IDs are 32 random hex characters', () => {
  const ids = new Set(Array.from({ length: 100 }, newCallId));
  assert.equal(ids.size, 100);
  for (const id of ids) assert.match(id, /^[0-9a-f]{32}$/);
});

test('a damaged stored state is cleaned up', () => {
  assert.deepEqual(normalState(undefined), emptyState());
  assert.deepEqual(normalState('junk'), emptyState());
  assert.deepEqual(normalState({ callId: 'not-hex', calledAt: T0, day: '2026-11-20', count: 2 }),
    { callId: null, calledAt: null, day: '2026-11-20', count: 2 });
  assert.deepEqual(normalState({ callId: ID, calledAt: 'soon', day: 'today', count: 2 }), emptyState());
  assert.deepEqual(normalState({ callId: ID, calledAt: T0, day: '2026-11-20', count: -1 }),
    { callId: ID, calledAt: T0, day: null, count: 0 });
  assert.deepEqual(normalState({ callId: ID, calledAt: T0, day: '2026-11-20', count: 1.5 }),
    { callId: ID, calledAt: T0, day: null, count: 0 });
  const good = { callId: ID, calledAt: T0, day: '2026-11-20', count: 3 };
  assert.deepEqual(normalState(good), good);
});

test('calls on an earlier day don\'t count against today', () => {
  assert.deepEqual(checkLimits({ callId: null, calledAt: null, day: '2026-11-20', count: 4 }, T0 + 24 * HOUR), { ok: true });
});
