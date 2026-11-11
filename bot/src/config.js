// The bot's settings. They're typed into the Worker's page on Cloudflare
// (Settings > Variables and Secrets), never into this repo, so the code stays
// the same for anyone and a mistake in one shows up as a clear message.

import { isPublicKey } from './discord.js';

// A Discord ID number ("snowflake"): 17 to 20 digits.
export const SNOWFLAKE = /^\d{17,20}$/;

// The only Discord server the bot works in: SYNDICATE (discord.gg/syn-hll).
// Fixed here rather than in a setting, so it can't be pointed somewhere else.
export const SERVER_ID = '1117120667490455713';

// The most roles a call can ping (SEEDERS_ROLE_ID). The Privacy Policy says two.
export const MAX_PING_ROLES = 2;

// The settings' names, as they're typed on Cloudflare.
export const SETTING_NAMES = Object.freeze([
  'DISCORD_PUBLIC_KEY',
  'SYNSEEDER_CHANNEL_ID',
  'SEED_CALLER_ROLE_ID',
  'SEEDERS_ROLE_ID',
]);

// Reads the settings from ``env``.
// Returns { config, problems }, where problems lists the names of the
// settings that are missing or don't look right.
export function readConfig(env) {
  const value = name => String(env?.[name] ?? '').trim();
  const problems = [];
  const id = name => {
    const text = value(name);
    if (!SNOWFLAKE.test(text)) problems.push(name);
    return text;
  };

  const publicKey = value('DISCORD_PUBLIC_KEY').toLowerCase();
  if (!isPublicKey(publicKey)) problems.push('DISCORD_PUBLIC_KEY');
  const serverId = SERVER_ID;
  const channelId = id('SYNSEEDER_CHANNEL_ID');
  const seedCallerRoleId = id('SEED_CALLER_ROLE_ID');

  // The roles to ping are optional: one role ID, or two separated by a comma.
  // Left empty, the bot's reply pings nobody.
  const seeders = value('SEEDERS_ROLE_ID');
  let seedersRoleIds = seeders === '' ? [] : [...new Set(seeders.split(/[\s,]+/).filter(Boolean))];
  if (seedersRoleIds.length > MAX_PING_ROLES || !seedersRoleIds.every(roleId => SNOWFLAKE.test(roleId))) {
    problems.push('SEEDERS_ROLE_ID');
    seedersRoleIds = [];
  }

  return {
    config: { publicKey, serverId, channelId, seedCallerRoleId, seedersRoleIds },
    problems,
  };
}
