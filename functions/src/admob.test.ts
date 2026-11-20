import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { test } from 'node:test';
import { verifyAdmobCallback } from './admob';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pem = publicKey.export({ type: 'spki', format: 'pem' }).toString();

globalThis.fetch = (async () =>
  new Response(JSON.stringify({ keys: [{ keyId: 42, pem }] }))) as typeof fetch;

function signed(message: string): string {
  const signature = sign('sha256', Buffer.from(message), privateKey).toString('base64url');
  return `${message}&signature=${signature}&key_id=42`;
}

const message =
  'ad_network=5450213213286189855&ad_unit=1234&reward_amount=1&reward_item=name' +
  '&timestamp=1790000000000&transaction_id=abc123&user_id=uid42';

test('accepts a callback signed by a listed key', async () => {
  const params = await verifyAdmobCallback(signed(message));
  assert.equal(params?.get('user_id'), 'uid42');
  assert.equal(params?.get('transaction_id'), 'abc123');
});

test('rejects a callback whose signed part was changed', async () => {
  const forged = signed(message).replace('user_id=uid42', 'user_id=other');
  assert.equal(await verifyAdmobCallback(forged), null);
});

test('rejects an unsigned callback and an unknown key', async () => {
  assert.equal(await verifyAdmobCallback(message), null);
  assert.equal(await verifyAdmobCallback(signed(message).replace('key_id=42', 'key_id=7')), null);
});

test('ignores parameters smuggled after signature', async () => {
  const withoutUser =
    'ad_network=5450213213286189855&ad_unit=1234&reward_amount=1&reward_item=name' +
    '&timestamp=1790000000000&transaction_id=abc123';
  const smuggled = `${signed(withoutUser)}&user_id=attacker`;
  const params = await verifyAdmobCallback(smuggled);
  assert.ok(params);
  assert.equal(params.get('user_id'), null);
});
