// The whole Worker, as Cloudflare runs it: settings from env, the real
// SeedFlag class on a stand-in for Durable Object storage, and the stats page
// answered by a stand-in for fetch.
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker, { SeedFlag } from '../src/index.js';
import { CALLER, CHANNEL, CALLER_ROLE, SEEDERS_ROLE, discordRequest, getRequest, makeKeys, newCallId, seedCommand } from './helpers.js';
import { STATS_URL } from '../src/stats.js';

const keys = await makeKeys();

// Durable Object storage that copies values in and out, like the real one.
class MemoryStorage {
  constructor() { this.map = new Map(); }
  async get(key) { return this.map.has(key) ? structuredClone(this.map.get(key)) : undefined; }
  async put(key, value) { this.map.set(key, structuredClone(value)); }
}

// Like a real stub, each one from get() is a separate connection to the one
// object. After an error it stays broken, as Cloudflare's do.
class FakeStub {
  constructor(object, namespace) { this.object = object; this.namespace = namespace; this.broken = null; }
  get ctx() { return this.object.ctx; }
  async _use(method, args) {
    if (this.broken) throw this.broken;
    const result = await this.object[method](...args);
    if (method === 'call' && this.namespace.loseNextAnswer) {
      this.namespace.loseNextAnswer = false;
      this.broken = new Error('Network connection lost.');
      throw this.broken;
    }
    return result;
  }
  latest(...args) { return this._use('latest', args); }
  peek(...args) { return this._use('peek', args); }
  call(...args) { return this._use('call', args); }
}

class FakeNamespace {
  constructor() { this.objects = new Map(); this.names = []; this.loseNextAnswer = false; }
  idFromName(name) { this.names.push(name); return `id:${name}`; }
  get(id) {
    if (!this.objects.has(id)) this.objects.set(id, new SeedFlag({ storage: new MemoryStorage() }, {}));
    return new FakeStub(this.objects.get(id), this);
  }
}

let env;
let realFetch;
let players;
let statsCalls;

beforeEach(() => {
  env = {
    DISCORD_PUBLIC_KEY: keys.publicKey,
    SYNSEEDER_CHANNEL_ID: CHANNEL,
    SEED_CALLER_ROLE_ID: CALLER_ROLE,
    SEEDERS_ROLE_ID: SEEDERS_ROLE,
    SEED_FLAG: new FakeNamespace(),
  };
  players = 8;
  statsCalls = 0;
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, STATS_URL, 'the Worker only ever fetches the stats page');
    assert.equal(options.redirect, 'manual');
    statsCalls++;
    return new Response(JSON.stringify({ result: { player_count: players }, failed: false }));
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

async function interact(payload) {
  const response = await worker.fetch(await discordRequest(keys, payload, { now: Date.now() }), env);
  return response.json();
}

test('the Worker answers the PING, calls a seed, and the PCs see the call', async () => {
  assert.deepEqual(await interact({ type: 1 }), { type: 1 });

  const reply = await interact(seedCommand());
  assert.equal(reply.data.flags, undefined);
  assert.match(reply.data.content, new RegExp(`^<@&${SEEDERS_ROLE}> Seed called by <@${CALLER}>\\. The server has 8 players\\.`));
  assert.equal(statsCalls, 1);

  const seen = await (await worker.fetch(getRequest('/seed-call'), env)).json();
  assert.match(seen.call, /^[0-9a-f]{32}$/);
  assert.ok(seen.age >= 0 && seen.age < 5);

  // The flag is one object, found by one name, and holds nothing about people.
  assert.deepEqual(new Set(env.SEED_FLAG.names), new Set(['seed-call']));
  assert.equal(env.SEED_FLAG.objects.size, 1);
  const stored = [...env.SEED_FLAG.objects.values()][0].ctx.storage.map;  // the one object
  assert.deepEqual([...stored.keys()], ['state']);
  // Exactly what PRIVACY.md lists: the call's random number, when it was made,
  // and how many calls were made that day.
  assert.deepEqual(Object.keys(stored.get('state')).sort(), ['callId', 'calledAt', 'count', 'day']);
  assert.equal(stored.get('state').count, 1);
  assert.ok(!JSON.stringify(stored.get('state')).includes(CALLER), 'the caller is not stored');
});

test('if the answer to a stored call is lost, a new connection finds it and the call is announced', async () => {
  env.SEED_FLAG.loseNextAnswer = true;
  const reply = await interact(seedCommand());
  assert.equal(reply.data.flags, undefined);
  assert.match(reply.data.content, new RegExp(`^<@&${SEEDERS_ROLE}> Seed called by <@${CALLER}>\\.`));
  const seen = await (await worker.fetch(getRequest('/seed-call'), env)).json();
  assert.match(seen.call, /^[0-9a-f]{32}$/);
});

test('a second /seed straight after is refused by the real flag', async () => {
  await interact(seedCommand());
  const again = await interact(seedCommand());
  assert.equal(again.data.flags, 64);
  assert.match(again.data.content, /less than 30 minutes ago/);
  assert.equal(statsCalls, 1, 'the refusal came before the stats page');
});

test('the Worker names a missing setting instead of failing', async () => {
  delete env.SEED_CALLER_ROLE_ID;
  const reply = await interact(seedCommand());
  assert.equal(reply.data.flags, 64);
  assert.match(reply.data.content, /SEED_CALLER_ROLE_ID/);
  assert.equal(statsCalls, 0);
});

test('a damaged flag in storage is treated as no call', async () => {
  const flag = env.SEED_FLAG.get(env.SEED_FLAG.idFromName('seed-call'));
  await flag.ctx.storage.put('state', { callId: 42, calledAt: 'soon', day: 7, count: 'lots' });
  assert.equal(await flag.latest(), null);
  assert.deepEqual(await flag.peek(), { ok: true });
});

test('the real flag refuses a call past its deadline and stores nothing', async () => {
  const flag = env.SEED_FLAG.get(env.SEED_FLAG.idFromName('seed-call'));
  const id = newCallId();
  assert.deepEqual(await flag.call(Date.now() - 1, id), { ok: false, reason: 'late' });
  assert.deepEqual(await flag.call(undefined, id), { ok: false, reason: 'late' }, 'a missing deadline counts as passed');
  assert.equal(flag.ctx.storage.map.size, 0);
  const made = await flag.call(Date.now() + 2000, id);
  assert.equal(made.ok, true);
  assert.equal(made.id, id, 'the flag stores the ID the Worker made');
  assert.equal((await flag.latest()).id, id);
});

test('the real flag refuses a call without a proper ID', async () => {
  const flag = env.SEED_FLAG.get(env.SEED_FLAG.idFromName('seed-call'));
  await assert.rejects(flag.call(Date.now() + 2000, 'not-an-id'), TypeError);
  await assert.rejects(flag.call(Date.now() + 2000), TypeError);
  assert.equal(flag.ctx.storage.map.size, 0);
});
