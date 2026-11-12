import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CALL_DEADLINE_MS, CALL_TEXT, REPLY_DEADLINE_MS, handleRequest, SeedCallCache } from '../src/handler.js';
import {
  CALLER, CALLER_ROLE, CHANNEL, HOUR, MINUTE, OTHER_CHANNEL, SEEDERS_ROLE, SERVER,
  discordRequest, getRequest, makeDeps, makeKeys, newCallId, seedCommand,
} from './helpers.js';

const keys = await makeKeys();

async function run(deps, payload, options = {}) {
  const response = await handleRequest(await discordRequest(keys, payload, { now: deps.clock.now, ...options }), deps);
  const type = response.headers.get('Content-Type') ?? '';
  return { status: response.status, body: type.startsWith('application/json') ? await response.json() : await response.text() };
}

async function seedCall(deps) {
  const response = await handleRequest(getRequest('/seed-call'), deps);
  return { status: response.status, cache: response.headers.get('Cache-Control'), body: await response.json() };
}

function assertPrivate(body, pattern) {
  assert.equal(body.type, 4);
  assert.equal(body.data.flags, 64, 'a refusal is seen only by the caller');
  assert.deepEqual(body.data.allowed_mentions, { parse: [] }, 'a refusal pings nobody');
  assert.match(body.data.content, pattern);
}

// Signatures and Discord's check of the address

test("Discord's PING is answered with a PONG", async () => {
  const deps = makeDeps(keys);
  assert.deepEqual(await run(deps, { type: 1 }), { status: 200, body: { type: 1 } });
});

test('the PING works on the bare address too', async () => {
  const deps = makeDeps(keys);
  assert.deepEqual(await run(deps, { type: 1 }, { path: '/' }), { status: 200, body: { type: 1 } });
});

test('the PING works before the IDs are filled in', async () => {
  const deps = makeDeps(keys);
  deps.problems = ['SYNSEEDER_CHANNEL_ID', 'SEED_CALLER_ROLE_ID'];
  assert.deepEqual(await run(deps, { type: 1 }), { status: 200, body: { type: 1 } });
});

test('a bad signature is refused with 401', async () => {
  const deps = makeDeps(keys);
  assert.equal((await run(deps, { type: 1 }, { badSignature: true })).status, 401);
  assert.equal((await run(deps, seedCommand(), { badSignature: true })).status, 401);
  assert.equal(deps.flag.calls.call, 0);
});

test('a request signed with another app\'s key is refused', async () => {
  const deps = makeDeps(keys);
  const other = await makeKeys();
  const response = await handleRequest(await discordRequest(other, { type: 1 }, { now: deps.clock.now }), deps);
  assert.equal(response.status, 401);
});

test('a request without signature headers is refused', async () => {
  const deps = makeDeps(keys);
  const request = new Request('https://synseeder.example.workers.dev/interactions', { method: 'POST', body: '{"type":1}' });
  assert.equal((await handleRequest(request, deps)).status, 401);
});

test('a signature more than 5 minutes old or ahead is refused', async () => {
  const deps = makeDeps(keys);
  const stamp = seconds => String(Math.floor(deps.clock.now / 1000) + seconds);
  assert.equal((await run(deps, { type: 1 }, { timestamp: stamp(-301) })).status, 401);
  assert.equal((await run(deps, { type: 1 }, { timestamp: stamp(301) })).status, 401);
  assert.equal((await run(deps, { type: 1 }, { timestamp: stamp(-299) })).status, 200);
});

test('a body changed after signing is refused', async () => {
  const deps = makeDeps(keys);
  const good = await discordRequest(keys, { type: 1 }, { now: deps.clock.now });
  const tampered = new Request(good.url, { method: 'POST', headers: good.headers, body: '{"type":1 }' });
  assert.equal((await handleRequest(tampered, deps)).status, 401);
});

test('without a Public Key setting everything is refused with 401, and the setting is named', async () => {
  const deps = makeDeps(keys);
  deps.problems = ['DISCORD_PUBLIC_KEY'];
  const result = await run(deps, { type: 1 });
  assert.equal(result.status, 401);
  assert.match(result.body, /DISCORD_PUBLIC_KEY/);
});

test('signed junk is refused', async () => {
  const deps = makeDeps(keys);
  assert.equal((await run(deps, 'not json')).status, 400);
  assert.equal((await run(deps, { type: 3 })).status, 400);
});

// /seed

test('a Syngineer calls a seed, and the reply pings the chosen role, without naming the caller', async () => {
  const deps = makeDeps(keys);
  const { status, body } = await run(deps, seedCommand());
  assert.equal(status, 200);
  assert.equal(body.type, 4);
  assert.equal(body.data.flags, undefined, 'the call is public');
  assert.equal(body.data.content, `<@&${SEEDERS_ROLE}> Time to hop in the Syndicate | Competitive Server to get it seeded!`);
  assert.equal(body.data.content, `<@&${SEEDERS_ROLE}> ${CALL_TEXT}`);
  assert.ok(!body.data.content.includes(CALLER), 'the caller is not named');
  assert.deepEqual(body.data.allowed_mentions, { parse: [], users: [], roles: [SEEDERS_ROLE] });
  assert.equal(deps.flag.calls.call, 1);
  assert.deepEqual(deps.flag.deadlines, [deps.clock.now + CALL_DEADLINE_MS], 'the flag is told the deadline');
  assert.match(deps.flag.state.callId, /^[0-9a-f]{32}$/);
});

test('the call reaches the PCs at once from the same copy of the Worker', async () => {
  const deps = makeDeps(keys);
  assert.deepEqual((await seedCall(deps)).body, { call: null });
  await run(deps, seedCommand());
  deps.clock.now += 30 * 1000;
  const { body } = await seedCall(deps);
  assert.match(body.call, /^[0-9a-f]{32}$/);
  assert.equal(body.age, 30);
  assert.equal(deps.flag.state.callId, body.call);
});

test('without a role to ping, the reply pings nobody', async () => {
  const deps = makeDeps(keys, { seeders: [] });
  const { body } = await run(deps, seedCommand());
  assert.equal(body.data.content, `${CALL_TEXT}`);
  assert.deepEqual(body.data.allowed_mentions, { parse: [], users: [], roles: [] });
});

test('with two roles to ping, the reply pings both, and only them', async () => {
  const other = '555555555555555555';
  const deps = makeDeps(keys, { seeders: [SEEDERS_ROLE, other] });
  const { body } = await run(deps, seedCommand());
  assert.equal(body.data.content, `<@&${SEEDERS_ROLE}> <@&${other}> ${CALL_TEXT}`);
  assert.deepEqual(body.data.allowed_mentions, { parse: [], users: [], roles: [SEEDERS_ROLE, other] });
});

test('someone without the Syngineers role is refused, admins included', async () => {
  const deps = makeDeps(keys);
  const admin = seedCommand();
  admin.member.roles = ['666666666666666666'];
  admin.member.permissions = '8';
  const { body } = await run(deps, admin);
  assertPrivate(body, new RegExp(`Only members with the <@&${CALLER_ROLE}> role`));
  assert.equal(deps.flag.calls.call, 0);
  assert.equal(deps.statsReads, 0);
});

test('a member object without roles is refused', async () => {
  const deps = makeDeps(keys);
  const { body } = await run(deps, seedCommand({ member: undefined, user: { id: CALLER } }));
  assertPrivate(body, /Only members with the/);
});

test('/seed in another channel is refused and points to the right one', async () => {
  const deps = makeDeps(keys);
  const { body } = await run(deps, seedCommand({ channel_id: OTHER_CHANNEL }));
  assertPrivate(body, new RegExp(`Use /seed in <#${CHANNEL}>`));
  assert.equal(deps.flag.calls.call, 0);
});

test('/seed in another server is refused', async () => {
  const deps = makeDeps(keys);
  const { body } = await run(deps, seedCommand({ guild_id: '121212121212121212' }));
  assertPrivate(body, /only works in the SYNDICATE Discord server/);
  const dm = seedCommand({ guild_id: undefined, member: undefined, user: { id: CALLER } });
  assertPrivate((await run(deps, dm)).body, /only works in the SYNDICATE/);
  assert.equal(deps.flag.calls.call, 0);
});

test('another command name is refused', async () => {
  const deps = makeDeps(keys);
  const { body } = await run(deps, seedCommand({ data: { name: 'unseed', type: 1 } }));
  assertPrivate(body, /only knows \/seed/);
});

test('missing settings are named in the refusal', async () => {
  const deps = makeDeps(keys);
  deps.problems = ['SYNSEEDER_CHANNEL_ID', 'SEEDERS_ROLE_ID'];
  const { body } = await run(deps, seedCommand());
  assertPrivate(body, /SYNSEEDER_CHANNEL_ID, SEEDERS_ROLE_ID/);
  assert.equal(deps.flag.calls.call, 0);
});

test('at 50 players or more, no seed is called', async () => {
  const deps = makeDeps(keys, { players: 50 });
  assertPrivate((await run(deps, seedCommand())).body, /has 50 players, so it doesn't need a seed/);
  deps.players = 49;
  assert.equal((await run(deps, seedCommand())).body.data.flags, undefined);
});

test("if the player count can't be read, no seed is called", async () => {
  const deps = makeDeps(keys, { players: new Error('timeout') });
  assertPrivate((await run(deps, seedCommand())).body, /couldn't read the server's player count/);
  assert.equal(deps.flag.calls.call, 0);
});

test('a second call within 30 minutes is refused, with when the next can be made', async () => {
  const deps = makeDeps(keys);
  const first = deps.clock.now;
  await run(deps, seedCommand());
  deps.clock.now += 10 * MINUTE;
  const { body } = await run(deps, seedCommand());
  assertPrivate(body, new RegExp(`less than 30 minutes ago\\. The next one can be called <t:${first / 1000 + 1800}:R>`));
  assert.equal(deps.statsReads, 1, 'a refused call costs no stats read');
  deps.clock.now = first + 30 * MINUTE;
  assert.equal((await run(deps, seedCommand())).body.data.flags, undefined);
});

test('straight after the day\'s 4th call, the refusal says midnight, not 30 minutes', async () => {
  const deps = makeDeps(keys);
  const first = deps.clock.now;
  for (let i = 0; i < 4; i++) {
    deps.clock.now = first + i * HOUR;
    await run(deps, seedCommand());
  }
  deps.clock.now = first + 3 * HOUR + 10 * MINUTE;
  assertPrivate((await run(deps, seedCommand())).body,
    new RegExp(`4 seeds have been called today .* <t:${Date.UTC(2026, 10, 21, 5, 0, 0) / 1000}:R>`));
});

test('a fifth call on the same day is refused until midnight US Eastern', async () => {
  const deps = makeDeps(keys);  // 1:00 pm US Eastern on 20 November 2026
  const first = deps.clock.now;
  for (let i = 0; i < 4; i++) {
    deps.clock.now = first + i * HOUR;
    assert.equal((await run(deps, seedCommand())).body.data.flags, undefined);
  }
  deps.clock.now = first + 4 * HOUR;
  const midnight = Date.UTC(2026, 10, 21, 5, 0, 0) / 1000;
  assertPrivate((await run(deps, seedCommand())).body,
    new RegExp(`4 seeds have been called today \\(US Eastern time\\)\\. The next one can be called <t:${midnight}:R>`));
  deps.clock.now = midnight * 1000;
  assert.equal((await run(deps, seedCommand())).body.data.flags, undefined);
});

test('if another call lands while the player count is read, the flag still refuses', async () => {
  const deps = makeDeps(keys);
  deps.readPlayers = async () => {
    await deps.flag.call(Infinity, newCallId());  // someone else's /seed gets in first
    return 12;
  };
  assertPrivate((await run(deps, seedCommand())).body, /less than 30 minutes ago/);
});

test('if the stats page and the flag take too long, no seed is called', async () => {
  const deps = makeDeps(keys);
  deps.readPlayers = async () => {
    deps.clock.now += CALL_DEADLINE_MS + 1;
    return 12;
  };
  assertPrivate((await run(deps, seedCommand())).body, /^That took too long, so no seed was called\. Try again\.$/);
  assert.equal(deps.flag.calls.call, 0, 'the flag is not even asked');
  assert.equal(deps.flag.state.callId, null);
});

test("if the limit check doesn't answer in time, the caller is told before Discord gives up", async () => {
  const deps = makeDeps(keys);
  const arrivedAt = deps.clock.now;
  deps.flag.peek = () => {
    deps.clock.now = arrivedAt + CALL_DEADLINE_MS - 100;  // 100 ms left
    return new Promise(() => {});  // never answers
  };
  const start = Date.now();
  assertPrivate((await run(deps, seedCommand())).body, /^That took too long, so no seed was called/);
  assert.ok(Date.now() - start < 1000, 'it waited only for the time that was left');
  assert.equal(deps.statsReads, 0);
  assert.equal(deps.flag.calls.call, 0);
});

test('if the limit check answers only after the deadline, the stats page is not read', async () => {
  const deps = makeDeps(keys);
  const peek = deps.flag.peek.bind(deps.flag);
  deps.flag.peek = async () => {
    deps.clock.now += CALL_DEADLINE_MS + 1;
    return peek();
  };
  assertPrivate((await run(deps, seedCommand())).body, /^That took too long, so no seed was called/);
  assert.equal(deps.statsReads, 0);
});

test("if the stats page doesn't answer in time, the caller is told before Discord gives up", async () => {
  const deps = makeDeps(keys);
  const arrivedAt = deps.clock.now;
  deps.readPlayers = () => {
    deps.clock.now = arrivedAt + CALL_DEADLINE_MS - 100;  // the flag was slow: 100 ms left
    return new Promise(() => {});  // never answers
  };
  const start = Date.now();
  assertPrivate((await run(deps, seedCommand())).body, /^That took too long, so no seed was called/);
  assert.ok(Date.now() - start < 1000, 'it waited only for the time that was left');
  assert.equal(deps.flag.calls.call, 0);
});

test('just inside the deadline, the seed is called', async () => {
  const deps = makeDeps(keys);
  deps.readPlayers = async () => {
    deps.clock.now += CALL_DEADLINE_MS;
    return 12;
  };
  assert.equal((await run(deps, seedCommand())).body.data.flags, undefined);
});

test('if the call to the flag itself is late, the flag refuses it', async () => {
  const deps = makeDeps(keys);
  const call = deps.flag.call.bind(deps.flag);
  deps.flag.call = async (deadline, id) => {
    deps.clock.now = deadline + 1;  // a slow or retried call
    return call(deadline, id);
  };
  assertPrivate((await run(deps, seedCommand())).body, /^That took too long, so no seed was called/);
  assert.equal(deps.flag.state.callId, null);
});

// The flag's answer to a call can get lost after the call was stored.
function loseAnswer(deps, { stored }) {
  const call = deps.flag.call.bind(deps.flag);
  deps.flag.call = async (deadline, id) => {
    if (stored) await call(deadline, id);
    throw new Error('Network connection lost.');
  };
  const fresh = { asked: 0 };
  deps.freshFlag = () => {
    fresh.asked++;
    return deps.flag;
  };
  return fresh;
}

test('if the answer is lost after the call was stored, the public reply is still sent', async () => {
  const deps = makeDeps(keys);
  const fresh = loseAnswer(deps, { stored: true });
  const { status, body } = await run(deps, seedCommand());
  assert.equal(status, 200);
  assert.equal(fresh.asked, 1, 'a fresh connection to the flag is asked');
  assert.equal(body.data.flags, undefined);
  assert.equal(body.data.content, `<@&${SEEDERS_ROLE}> ${CALL_TEXT}`);
  assert.equal((await seedCall(deps)).body.call, deps.flag.state.callId);
});

test('if the answer is lost and the call was not stored, the caller is told no seed was called', async () => {
  const deps = makeDeps(keys);
  loseAnswer(deps, { stored: false });
  assertPrivate((await run(deps, seedCommand())).body, /^Something went wrong, so no seed was called\. Try again in a minute\.$/);
});

test('if the answer is lost and an earlier call is still live, ours was not stored', async () => {
  const deps = makeDeps(keys);
  await deps.flag.call(Infinity, newCallId());
  deps.flag.peek = async () => ({ ok: true });  // as if the earlier call came in meanwhile
  loseAnswer(deps, { stored: false });
  assertPrivate((await run(deps, seedCommand())).body, /^Something went wrong, so no seed was called/);
});

test("if the answer is lost and the flag can't be asked again, the channel is told", async () => {
  const deps = makeDeps(keys);
  loseAnswer(deps, { stored: true });
  deps.freshFlag = () => ({ latest: async () => { throw new Error('Network connection lost.'); } });
  const { body } = await run(deps, seedCommand());
  assert.equal(body.data.flags, undefined, 'the channel sees it');
  assert.equal(body.data.content, "Someone tried to call a seed, but something went wrong, and I can't tell whether it went through. "
    + 'If it did, PCs with **Seed when pinged** ticked will start joining, and the call ends within 15 minutes.');
  assert.deepEqual(body.data.allowed_mentions, { parse: [], users: [], roles: [] }, 'it pings nobody');
});

test("if the flag doesn't answer the second look in time, the channel is told before Discord gives up", async () => {
  const deps = makeDeps(keys);
  loseAnswer(deps, { stored: true });
  const start = Date.now();
  deps.freshFlag = () => ({ latest: () => new Promise(() => {}) });  // never answers
  deps.flag.call = async () => {
    deps.clock.now += REPLY_DEADLINE_MS - 150;  // leaves 150 ms
    throw new Error('Network connection lost.');
  };
  const { body } = await run(deps, seedCommand());
  assert.match(body.data.content, /can't tell whether it went through/);
  assert.ok(Date.now() - start < 1000, 'it waited only for the time that was left');
});

test("if the flag doesn't answer the call in time, the channel is told before Discord gives up", async () => {
  const deps = makeDeps(keys);
  const arrivedAt = deps.clock.now;
  deps.readPlayers = async () => {
    deps.clock.now = arrivedAt + CALL_DEADLINE_MS;  // just in time to call
    return 12;
  };
  const call = deps.flag.call.bind(deps.flag);
  deps.flag.call = async (deadline, id) => {
    await call(deadline, id);  // stored, but the answer never comes back
    return new Promise(() => {});
  };
  const start = Date.now();
  const { body } = await run(deps, seedCommand());
  const waited = Date.now() - start;
  assert.match(body.data.content, /^Someone tried to call a seed, but something went wrong, and I can't tell whether it went through/);
  assert.equal(body.data.flags, undefined, 'the channel sees it');
  assert.deepEqual(body.data.allowed_mentions, { parse: [], users: [], roles: [] });
  assert.ok(waited >= REPLY_DEADLINE_MS - CALL_DEADLINE_MS - 50 && waited < 1000, `it waited only for the time that was left (${waited} ms)`);
});

test('if the answer is lost with no time left, the channel is told without asking again', async () => {
  const deps = makeDeps(keys);
  const fresh = loseAnswer(deps, { stored: true });
  deps.flag.call = async () => {
    deps.clock.now += REPLY_DEADLINE_MS;
    throw new Error('Network connection lost.');
  };
  assert.match((await run(deps, seedCommand())).body.data.content, /can't tell whether it went through/);
  assert.equal(fresh.asked, 0);
});

test('if the flag fails before calling, the caller is told no seed was called', async () => {
  const deps = makeDeps(keys);
  deps.flag.peek = async () => { throw new Error('storage down'); };
  const { status, body } = await run(deps, seedCommand());
  assert.equal(status, 200);
  assertPrivate(body, /Something went wrong, so no seed was called/);
  assert.equal(deps.flag.calls.call, 0);
});

// /seed-call

test('/seed-call says no call when there is none', async () => {
  const deps = makeDeps(keys);
  assert.deepEqual(await seedCall(deps), { status: 200, cache: 'no-store', body: { call: null } });
});

test('/seed-call stops showing a call after 15 minutes', async () => {
  const deps = makeDeps(keys);
  await run(deps, seedCommand());
  deps.clock.now += 15 * MINUTE - 1000;
  assert.equal((await seedCall(deps)).body.age, 899);
  deps.clock.now += 1000;
  assert.deepEqual((await seedCall(deps)).body, { call: null });
});

test('/seed-call asks the flag at most once per 10 seconds per copy of the Worker', async () => {
  const deps = makeDeps(keys);
  for (let i = 0; i < 5; i++) await seedCall(deps);
  assert.equal(deps.flag.calls.latest, 1);
  deps.clock.now += 10 * 1000;
  await seedCall(deps);
  assert.equal(deps.flag.calls.latest, 2);
});

test('a call made through another copy of the Worker reaches the PCs within 10 seconds', async () => {
  const deps = makeDeps(keys);
  assert.deepEqual((await seedCall(deps)).body, { call: null });
  await deps.flag.call(Infinity, newCallId());  // the /seed went to another copy
  deps.clock.now += 9 * 1000;
  assert.deepEqual((await seedCall(deps)).body, { call: null });
  deps.clock.now += 1000;
  assert.equal((await seedCall(deps)).body.age, 10);
});

test('/seed-call answers 503 if the flag fails', async () => {
  const deps = makeDeps(keys);
  deps.flag.latest = async () => { throw new Error('storage down'); };
  const { status, body } = await seedCall(deps);
  assert.equal(status, 503);
  assert.deepEqual(body, { error: 'unavailable' });
});

// Other addresses

test('the front page says it is running', async () => {
  const deps = makeDeps(keys);
  const response = await handleRequest(getRequest('/'), deps);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /running/);
});

test('wrong methods and unknown addresses are refused', async () => {
  const deps = makeDeps(keys);
  assert.equal((await handleRequest(getRequest('/seed-call', 'POST'), deps)).status, 405);
  assert.equal((await handleRequest(getRequest('/interactions'), deps)).status, 405);
  assert.equal((await handleRequest(getRequest('/', 'PUT'), deps)).status, 405);
  assert.equal((await handleRequest(getRequest('/admin'), deps)).status, 404);
});

test('the cache forgets a call after its time and after a clock jump back', () => {
  const cache = new SeedCallCache(10_000);
  assert.equal(cache.get(1000), undefined);
  cache.remember(null, 1000);
  assert.equal(cache.get(5000), null);
  assert.equal(cache.get(11_000), undefined);
  assert.equal(cache.get(500), undefined);
});

test('the server and caller IDs in the test data are distinct', () => {
  assert.equal(new Set([SERVER, CHANNEL, OTHER_CHANNEL, CALLER_ROLE, SEEDERS_ROLE, CALLER]).size, 6);
});
