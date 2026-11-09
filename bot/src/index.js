// The SynSeeder bot: one Cloudflare Worker that answers Discord's /seed
// command and tells SynSeeder PCs whether a seed has been called.
// See README.md in this folder for what it does and how to set it up.

import { readConfig } from './config.js';
import { SeedFlag } from './flag.js';
import { handleRequest, SeedCallCache } from './handler.js';
import { readPlayers } from './stats.js';

// Cloudflare needs the Durable Object's class exported from here.
export { SeedFlag };

// Shared by the requests this copy of the Worker handles.
const cache = new SeedCallCache();

export default {
  async fetch(request, env) {
    const { config, problems } = readConfig(env);
    // Every request uses the same single flag, found by its name.
    const getFlag = () => env.SEED_FLAG.get(env.SEED_FLAG.idFromName('seed-call'));
    return handleRequest(request, {
      config,
      problems,
      flag: getFlag(),
      freshFlag: getFlag,
      readPlayers: () => readPlayers(),
      cache,
      now: () => Date.now(),
    });
  },
};
