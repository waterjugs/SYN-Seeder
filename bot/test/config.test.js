import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readConfig, SETTING_NAMES } from '../src/config.js';

const KEY = 'a'.repeat(64);
const good = {
  DISCORD_PUBLIC_KEY: KEY,
  DISCORD_SERVER_ID: '111111111111111111',
  SYNSEEDER_CHANNEL_ID: '222222222222222222',
  SEED_CALLER_ROLE_ID: '333333333333333333',
  SEEDERS_ROLE_ID: '444444444444444444',
};

test('good settings are read', () => {
  assert.deepEqual(readConfig(good), {
    config: {
      publicKey: KEY,
      serverId: '111111111111111111',
      channelId: '222222222222222222',
      seedCallerRoleId: '333333333333333333',
      seedersRoleId: '444444444444444444',
    },
    problems: [],
  });
});

test('spaces around a pasted value are ignored, and the key is read in any case', () => {
  const { config, problems } = readConfig({ ...good, DISCORD_PUBLIC_KEY: `  ${'AB'.repeat(32)}\n`, DISCORD_SERVER_ID: ' 111111111111111111 ' });
  assert.deepEqual(problems, []);
  assert.equal(config.publicKey, 'ab'.repeat(32));
  assert.equal(config.serverId, '111111111111111111');
});

test('every missing setting is named, except the optional Seeders role', () => {
  assert.deepEqual(readConfig({}).problems, ['DISCORD_PUBLIC_KEY', 'DISCORD_SERVER_ID', 'SYNSEEDER_CHANNEL_ID', 'SEED_CALLER_ROLE_ID']);
  assert.deepEqual(readConfig(undefined).problems.length, 4);
});

test('an empty Seeders role means no ping', () => {
  const { config, problems } = readConfig({ ...good, SEEDERS_ROLE_ID: '' });
  assert.deepEqual(problems, []);
  assert.equal(config.seedersRoleId, null);
});

test('values that are not IDs or keys are reported', () => {
  const { problems } = readConfig({
    ...good,
    DISCORD_PUBLIC_KEY: 'not a key',
    DISCORD_SERVER_ID: '1234',
    SYNSEEDER_CHANNEL_ID: '#synseeder',
    SEED_CALLER_ROLE_ID: '<@&333333333333333333>',
    SEEDERS_ROLE_ID: 'Seeders',
  });
  assert.deepEqual(problems, SETTING_NAMES);
});
