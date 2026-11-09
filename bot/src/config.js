// The bot's settings. They're typed into the Worker's page on Cloudflare
// (Settings > Variables and Secrets), never into this repo, so the code stays
// the same for anyone and a mistake in one shows up as a clear message.

import { isPublicKey } from './discord.js';

// A Discord ID number ("snowflake"): 17 to 20 digits.
export const SNOWFLAKE = /^\d{17,20}$/;

// The settings' names, as they're typed on Cloudflare.
export const SETTING_NAMES = Object.freeze([
  'DISCORD_PUBLIC_KEY',
  'DISCORD_SERVER_ID',
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
  const serverId = id('DISCORD_SERVER_ID');
  const channelId = id('SYNSEEDER_CHANNEL_ID');
  const seedCallerRoleId = id('SEED_CALLER_ROLE_ID');

  // The Seeders role is optional: left empty, the bot's reply pings nobody.
  let seedersRoleId = null;
  const seeders = value('SEEDERS_ROLE_ID');
  if (seeders !== '') {
    if (SNOWFLAKE.test(seeders)) seedersRoleId = seeders;
    else problems.push('SEEDERS_ROLE_ID');
  }

  return {
    config: { publicKey, serverId, channelId, seedCallerRoleId, seedersRoleId },
    problems,
  };
}
