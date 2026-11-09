import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readConfig, SERVER_ID, SETTING_NAMES } from '../src/config.js';

const KEY = 'a'.repeat(64);
const good = {
  DISCORD_PUBLIC_KEY: KEY,
  SYNSEEDER_CHANNEL_ID: '222222222222222222',
  SEED_CALLER_ROLE_ID: '333333333333333333',
  SEEDERS_ROLE_ID: '444444444444444444',
};

test('good settings are read', () => {
  assert.deepEqual(readConfig(good), {
    config: {
      publicKey: KEY,
      serverId: SERVER_ID,
      channelId: '222222222222222222',
      seedCallerRoleId: '333333333333333333',
      seedersRoleId: '444444444444444444',
    },
    problems: [],
  });
});

test('spaces around a pasted value are ignored, and the key is read in any case', () => {
  const { config, problems } = readConfig({ ...good, DISCORD_PUBLIC_KEY: `  ${'AB'.repeat(32)}\n`, SYNSEEDER_CHANNEL_ID: ' 222222222222222222 ' });
  assert.deepEqual(problems, []);
  assert.equal(config.publicKey, 'ab'.repeat(32));
  assert.equal(config.channelId, '222222222222222222');
});

test('the bot works only in the SYNDICATE server, whatever the settings say', () => {
  assert.equal(SERVER_ID, '1117120667490455713');
  assert.equal(readConfig({ ...good, DISCORD_SERVER_ID: '111111111111111111' }).config.serverId, SERVER_ID);
  assert.equal(readConfig({}).config.serverId, SERVER_ID);
});

test('every missing setting is named, except the optional role to ping', () => {
  assert.deepEqual(readConfig({}).problems, ['DISCORD_PUBLIC_KEY', 'SYNSEEDER_CHANNEL_ID', 'SEED_CALLER_ROLE_ID']);
  assert.deepEqual(readConfig(undefined).problems.length, 3);
});

test('an empty SEEDERS_ROLE_ID means no ping', () => {
  const { config, problems } = readConfig({ ...good, SEEDERS_ROLE_ID: '' });
  assert.deepEqual(problems, []);
  assert.equal(config.seedersRoleId, null);
});

test('values that are not IDs or keys are reported', () => {
  const { problems } = readConfig({
    ...good,
    DISCORD_PUBLIC_KEY: 'not a key',
    SYNSEEDER_CHANNEL_ID: '#synseeder',
    SEED_CALLER_ROLE_ID: '<@&333333333333333333>',
    SEEDERS_ROLE_ID: 'Seeders',
  });
  assert.deepEqual(problems, SETTING_NAMES);
});
