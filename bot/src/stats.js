// The game server's player count, from the same public stats page the app reads.

// Fixed here rather than in a setting, so it can't be pointed somewhere else.
export const STATS_URL = 'https://syn-stats-nam.radicalgamingstats.com/api/get_public_info';

// Discord wants an answer within 3 seconds, so the stats page gets less than 2.
export const STATS_TIMEOUT_MS = 1800;

// The player count in the stats page's JSON. Throws if there isn't a sensible one.
export function parsePlayers(payload) {
  if (!payload || typeof payload !== 'object') throw new Error('the stats page sent no JSON object');
  if (payload.failed) throw new Error('the stats page reported a failure');
  const result = payload.result;
  if (!result || typeof result !== 'object') throw new Error('the stats page sent no result');
  let count = result.player_count;
  if (typeof count === 'string' && /^\d{1,4}$/.test(count)) count = Number(count);
  if (!Number.isInteger(count) || count < 0 || count > 1000) throw new Error('the stats page sent no player count');
  return count;
}

// Reads the player count now. Throws if the page can't be read in time.
export async function readPlayers(fetchImpl = fetch, timeoutMs = STATS_TIMEOUT_MS) {
  const response = await fetchImpl(STATS_URL, {
    headers: { Accept: 'application/json', 'User-Agent': 'SynSeeder bot' },
    // Cloudflare's fetch can't refuse redirects itself, so it's told not to
    // follow them, and a redirect then fails the response.ok check below.
    redirect: 'manual',
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`the stats page answered ${response.status}`);
  const text = await response.text();
  if (text.length > 1_000_000) throw new Error('the stats page sent too much');
  return parsePlayers(JSON.parse(text));
}
