// What the Worker does with each request. Everything it needs comes in
// ``deps``, so the tests can run it without Cloudflare or Discord:
//   config, problems  from readConfig()
//   flag              the seed-call flag: latest(), peek(), call()
//   freshFlag         () => a new connection to the same flag
//   readPlayers       async () => the game server's player count (throws if it can't)
//   cache             a SeedCallCache shared between requests
//   now               () => Date.now()
//
// Addresses:
//   POST /interactions (or /)  Discord's Interactions Endpoint URL
//   GET  /seed-call            what the PCs check about once a minute
//   GET  /                     a short "it's running" page

import { verifyRequest } from './discord.js';
import { LIMITS, newCallId, seedCallBody } from './rules.js';

const PING = 1;
const APPLICATION_COMMAND = 2;
const PONG = 1;
const CHANNEL_MESSAGE = 4;
const EPHEMERAL = 1 << 6;

// Interaction payloads are a few kilobytes; anything far bigger isn't Discord.
const MAX_BODY_CHARS = 64 * 1024;

// Discord throws away a reply that comes more than 3 seconds after it sent
// /seed. A seed is called only if the flag can store it this soon after the
// request arrived, so the reply announcing the call still reaches the channel.
export const CALL_DEADLINE_MS = 2200;
// And every answer to /seed must be ready this soon after the request arrived.
export const REPLY_DEADLINE_MS = 2700;

// Remembers the flag for a few seconds, so the PCs' checks don't each have to
// ask the Durable Object. A new call can reach the PCs this much later.
export class SeedCallCache {
  constructor(ttlMs = 10 * 1000) {
    this.ttlMs = ttlMs;
    this.at = 0;
    this.call = undefined;
  }

  // The remembered call (null for none), or undefined if it's too old to use.
  get(now) {
    if (this.call === undefined || now < this.at || now - this.at >= this.ttlMs) return undefined;
    return this.call;
  }

  remember(call, now) {
    this.call = call;
    this.at = now;
  }
}

export async function handleRequest(request, deps) {
  const path = new URL(request.url).pathname;
  if (path === '/interactions' || (path === '/' && request.method === 'POST')) {
    if (request.method !== 'POST') return text('Use POST.', 405, { Allow: 'POST' });
    return handleInteraction(request, deps);
  }
  if (path === '/seed-call') {
    if (request.method !== 'GET') return text('Use GET.', 405, { Allow: 'GET' });
    return seedCall(deps);
  }
  if (path === '/') {
    if (request.method !== 'GET') return text('Use GET.', 405, { Allow: 'GET, POST' });
    return text("SynSeeder's seed-call service is running.\n");
  }
  return text('Not found.', 404);
}

async function seedCall(deps) {
  const now = deps.now();
  try {
    let call = deps.cache.get(now);
    if (call === undefined) {
      call = await deps.flag.latest();
      deps.cache.remember(call, now);
    }
    return json(seedCallBody(call, now), 200, { 'Cache-Control': 'no-store' });
  } catch {
    return json({ error: 'unavailable' }, 503, { 'Cache-Control': 'no-store', 'Retry-After': '300' });
  }
}

async function handleInteraction(request, deps) {
  const arrivedAt = deps.now();
  // Only the Public Key is needed to answer Discord's check of the address,
  // so the address can be saved on the portal before the IDs are filled in.
  // Without it nothing can be checked, so everything is refused. (Discord
  // sends badly signed requests now and then to test the bot, and removes
  // the address from the portal if the answer is anything but 401.)
  if (deps.problems.includes('DISCORD_PUBLIC_KEY')) {
    return text('Bad request signature. (The bot is missing its DISCORD_PUBLIC_KEY setting.)', 401);
  }
  const body = await request.text();
  if (body.length > MAX_BODY_CHARS) return text('Too big.', 413);
  const signed = await verifyRequest(
    deps.config.publicKey,
    request.headers.get('X-Signature-Ed25519'),
    request.headers.get('X-Signature-Timestamp'),
    body,
    deps.now(),
  );
  if (!signed) return text('Bad request signature.', 401);

  let interaction;
  try {
    interaction = JSON.parse(body);
  } catch {
    return text('Bad JSON.', 400);
  }
  if (interaction?.type === PING) return json({ type: PONG });
  if (interaction?.type !== APPLICATION_COMMAND) return text('Not supported.', 400);
  try {
    return json(await seedCommand(interaction, deps, arrivedAt));
  } catch {
    return json(privateReply(NOT_CALLED));
  }
}

// The answer to /seed. Every refusal is seen only by the person who typed it.
// ``arrivedAt`` is when the request reached the Worker.
async function seedCommand(interaction, deps, arrivedAt) {
  if (interaction.data?.name !== 'seed') return privateReply('This bot only knows /seed.');
  const missing = deps.problems.filter(name => name !== 'DISCORD_PUBLIC_KEY');
  if (missing.length) {
    return privateReply(`The bot isn't set up yet. Its owner needs to check these settings on Cloudflare: ${missing.join(', ')}.`);
  }

  const { serverId, channelId, seedCallerRoleId, seedersRoleIds } = deps.config;
  if (interaction.guild_id !== serverId) return privateReply('/seed only works in the SYNDICATE Discord server.');
  if (interaction.channel_id !== channelId) return privateReply(`Use /seed in <#${channelId}>.`);
  const roles = interaction.member?.roles;
  if (!Array.isArray(roles) || !roles.includes(seedCallerRoleId)) {
    return privateReply(`Only members with the <@&${seedCallerRoleId}> role can call a seed.`);
  }

  // Every step before the call must be done by the deadline. Date.now() moves
  // on while Cloudflare waits for the flag and the stats page, so it shows
  // how long they took.
  const deadline = arrivedAt + CALL_DEADLINE_MS;

  // The limits are checked before the stats page, so a refused call costs nothing.
  const before = await within(deps.flag.peek(), deadline - deps.now());
  if (before === NO_ANSWER || deps.now() > deadline) return privateReply(TOO_SLOW);
  if (!before.ok) return privateReply(limitMessage(before));

  let players;
  try {
    players = await within(deps.readPlayers(), deadline - deps.now());
  } catch {
    return privateReply("I couldn't read the server's player count, so no seed was called. Try again in a minute.");
  }
  if (players === NO_ANSWER) return privateReply(TOO_SLOW);
  if (players >= LIMITS.maxPlayers) {
    return privateReply(`The server has ${players} players, so it doesn't need a seed. A seed can be called while it has fewer than ${LIMITS.maxPlayers}.`);
  }

  if (deps.now() > deadline) return privateReply(TOO_SLOW);

  // The flag checks the limits again, in case someone else called a seed
  // meanwhile, and the deadline again, in case the call to it was slow.
  const id = newCallId();
  const answerBy = arrivedAt + REPLY_DEADLINE_MS;
  let made;
  try {
    const timeLeft = answerBy - deps.now();
    made = await within(deps.flag.call(deadline, id), timeLeft);
  } catch {
    // The flag may have stored the call before its answer got lost.
    made = await lookAgain(deps, id, answerBy);
    if (made === null) return privateReply(NOT_CALLED);
  }
  // No answer in time: the call may be stored, and Discord won't wait.
  if (made === NO_ANSWER) return publicUnsure();
  if (!made.ok) return privateReply(made.reason === 'late' ? TOO_SLOW : limitMessage(made));
  deps.cache.remember({ id: made.id, calledAt: made.calledAt }, deps.now());
  return publicCall(seedersRoleIds);
}

// After the flag's answer to call ``id`` got lost: asks the flag, over a new
// connection (Cloudflare says not to reuse one that failed), what the latest
// call is. Returns the call as call() would have, null if it wasn't stored,
// or NO_ANSWER if the flag can't tell us before ``answerBy``.
async function lookAgain(deps, id, answerBy) {
  const timeLeft = answerBy - deps.now();
  if (timeLeft < 100) return NO_ANSWER;
  try {
    const latest = await within(deps.freshFlag().latest(), timeLeft);
    if (latest === NO_ANSWER) return NO_ANSWER;
    // A stored call is always the latest, because no other can follow it
    // within 30 minutes.
    return latest?.id === id ? { ok: true, id, calledAt: latest.calledAt } : null;
  } catch {
    return NO_ANSWER;
  }
}

const NO_ANSWER = Symbol('no answer in time');

// What ``promise`` gives, or NO_ANSWER if that takes more than ``ms``. Throws
// if it fails in time. A failure after that is ignored: nobody's waiting.
async function within(promise, ms) {
  promise.catch(() => {});
  let timer;
  try {
    return await Promise.race([promise, new Promise(resolve => { timer = setTimeout(() => resolve(NO_ANSWER), ms); })]);
  } finally {
    clearTimeout(timer);
  }
}

const NOT_CALLED = 'Something went wrong, so no seed was called. Try again in a minute.';

const TOO_SLOW = 'That took too long, so no seed was called. Try again.';

function limitMessage(verdict) {
  const when = `<t:${Math.ceil(verdict.retryAt / 1000)}:R>`;
  const minutes = LIMITS.cooldownMs / 60000;
  if (verdict.reason === 'cooldown') {
    return `A seed was called less than ${minutes} minutes ago. The next one can be called ${when}.`;
  }
  return `${LIMITS.callsPerDay} seeds have been called today (US Eastern time). The next one can be called ${when}.`;
}

// The message for a seed call, after the pings.
export const CALL_TEXT = 'Time to hop in the Syndicate | Competitive Server to get it seeded';

// The reply everyone in the channel sees. It pings only the roles in
// SEEDERS_ROLE_ID, if any. It doesn't name the caller: Discord already shows
// who used /seed above it.
function publicCall(seedersRoleIds) {
  const pings = seedersRoleIds.map(roleId => `<@&${roleId}> `).join('');
  return {
    type: CHANNEL_MESSAGE,
    data: {
      content: `${pings}${CALL_TEXT}`,
      allowed_mentions: { parse: [], users: [], roles: [...seedersRoleIds] },
    },
  };
}

// Said in the channel when a seed may have been called but the bot can't
// tell. Like the call itself, it doesn't name who tried. It pings nobody,
// since there may be no call.
function publicUnsure() {
  const minutes = LIMITS.callLifeMs / 60000;
  return {
    type: CHANNEL_MESSAGE,
    data: {
      content: "Someone tried to call a seed, but something went wrong, and I can't tell whether it went through. "
        + `If it did, PCs with **Seed when pinged** ticked will start joining, and the call ends within ${minutes} minutes.`,
      allowed_mentions: { parse: [], users: [], roles: [] },
    },
  };
}

function privateReply(content) {
  return {
    type: CHANNEL_MESSAGE,
    data: { content, flags: EPHEMERAL, allowed_mentions: { parse: [] } },
  };
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers },
  });
}

function text(body, status = 200, headers = {}) {
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', ...headers },
  });
}
