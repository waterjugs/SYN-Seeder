import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STATS_URL, parsePlayers, readPlayers } from '../src/stats.js';

test('the player count is read from a CRCON public info page', () => {
  assert.equal(parsePlayers({ result: { player_count: 37, player_count_by_team: { allied: 18, axis: 19 } }, failed: false }), 37);
  assert.equal(parsePlayers({ result: { player_count: '0' }, failed: false }), 0);
});

test('a failed or odd page throws', () => {
  for (const payload of [null, 'text', {}, { failed: true, result: { player_count: 3 } }, { result: {} },
    { result: { player_count: -1 } }, { result: { player_count: 3.5 } }, { result: { player_count: 5000 } }, { result: { player_count: '12a' } }]) {
    assert.throws(() => parsePlayers(payload), undefined, JSON.stringify(payload));
  }
});

test('the page is asked once, without following redirects, and with a time limit', async () => {
  const seen = [];
  const players = await readPlayers(async (url, options) => {
    seen.push({ url, options });
    return new Response(JSON.stringify({ result: { player_count: 21 }, failed: false }));
  });
  assert.equal(players, 21);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].url, STATS_URL);
  assert.equal(seen[0].options.redirect, 'manual');
  assert.ok(seen[0].options.signal instanceof AbortSignal);
});

test('an error page or a slow page throws', async () => {
  await assert.rejects(readPlayers(async () => new Response('busy', { status: 503 })));
  await assert.rejects(readPlayers(async () => new Response('<html>')));
  await assert.rejects(readPlayers(async () => new Response(null, { status: 302, headers: { Location: 'https://example.com/' } })));
  // Node doesn't wait for AbortSignal.timeout's timer, so a plain timer keeps the test alive.
  const keepAlive = setTimeout(() => {}, 5000);
  try {
    await assert.rejects(readPlayers((url, options) => new Promise((resolve, reject) => {
      options.signal.addEventListener('abort', () => reject(options.signal.reason));
    }), 20), { name: 'TimeoutError' });
  } finally {
    clearTimeout(keepAlive);
  }
});
