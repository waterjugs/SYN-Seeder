// Shared pieces for the tests: a signing key like Discord's, a stand-in for
// the seed-call flag, and ready-made interactions.

import { checkLimits, liveCall, newCallId, normalState, recordCall } from '../src/rules.js';
export { newCallId };
import { SeedCallCache } from '../src/handler.js';
import { SERVER_ID } from '../src/config.js';

export const SERVER = SERVER_ID;
export const CHANNEL = '222222222222222222';
export const OTHER_CHANNEL = '222222222222222229';
export const CALLER_ROLE = '333333333333333333';
export const SEEDERS_ROLE = '444444444444444444';
export const CALLER = '555555555555555555';

const hex = bytes => Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');

// An Ed25519 key pair, with its public key as hex (like the Developer Portal shows it).
export async function makeKeys() {
  const pair = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const publicKey = hex(await crypto.subtle.exportKey('raw', pair.publicKey));
  return { pair, publicKey };
}

export async function sign(keys, timestamp, body) {
  const signature = await crypto.subtle.sign({ name: 'Ed25519' }, keys.pair.privateKey, new TextEncoder().encode(timestamp + body));
  return hex(signature);
}

// A request signed the way Discord signs one.
export async function discordRequest(keys, payload, { now, path = '/interactions', timestamp, badSignature = false } = {}) {
  const body = typeof payload === 'string' ? payload : JSON.stringify(payload);
  const stamp = timestamp ?? String(Math.floor(now / 1000));
  let signature = await sign(keys, stamp, body);
  if (badSignature) signature = (signature[0] === '0' ? '1' : '0') + signature.slice(1);
  return new Request(`https://synseeder.example.workers.dev${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Signature-Ed25519': signature, 'X-Signature-Timestamp': stamp },
    body,
  });
}

// Works like the SeedFlag Durable Object, on a clock the test controls.
export class FakeFlag {
  constructor(clock) {
    this.clock = clock;
    this.state = normalState(null);
    this.calls = { latest: 0, peek: 0, call: 0 };
  }
  async latest() { this.calls.latest++; return liveCall(this.state, this.clock.now); }
  async peek() { this.calls.peek++; return checkLimits(this.state, this.clock.now); }
  async call(deadline, id) {
    this.calls.call++;
    this.deadlines = [...(this.deadlines ?? []), deadline];
    if (!/^[0-9a-f]{32}$/.test(id)) throw new TypeError('call() needs a call ID of 32 hex characters');
    if (!(this.clock.now <= deadline)) return { ok: false, reason: 'late' };
    const verdict = checkLimits(this.state, this.clock.now);
    if (!verdict.ok) return verdict;
    this.state = recordCall(this.state, this.clock.now, id);
    return { ok: true, id, calledAt: this.clock.now };
  }
}

export const MINUTE = 60 * 1000;
export const HOUR = 60 * MINUTE;

// Everything handleRequest needs, with settings that pass.
export function makeDeps(keys, { now = Date.UTC(2026, 10, 20, 18, 0, 0), players = 12, seeders = [SEEDERS_ROLE] } = {}) {
  const clock = { now };
  const deps = {
    clock,
    config: { publicKey: keys.publicKey, serverId: SERVER, channelId: CHANNEL, seedCallerRoleId: CALLER_ROLE, seedersRoleIds: seeders },
    problems: [],
    flag: new FakeFlag(clock),
    freshFlag: () => deps.flag,
    players,
    statsReads: 0,
    readPlayers: async () => {
      deps.statsReads++;
      if (deps.players instanceof Error) throw deps.players;
      return deps.players;
    },
    cache: new SeedCallCache(),
    now: () => clock.now,
  };
  return deps;
}

// A /seed command as Discord sends it, from a Syngineer in the right channel.
export function seedCommand(overrides = {}) {
  return {
    type: 2,
    id: '999999999999999999',
    application_id: '888888888888888888',
    token: 'interaction-token',
    guild_id: SERVER,
    channel_id: CHANNEL,
    data: { id: '777777777777777777', name: 'seed', type: 1 },
    member: {
      user: { id: CALLER, username: 'caller', global_name: 'Caller' },
      roles: [CALLER_ROLE],
      permissions: '0',
      joined_at: '2026-01-01T00:00:00.000000+00:00',
    },
    locale: 'en-US',
    ...overrides,
  };
}

export function getRequest(path, method = 'GET') {
  return new Request(`https://synseeder.example.workers.dev${path}`, { method });
}
