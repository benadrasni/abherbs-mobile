import assert from 'node:assert/strict';
import { test } from 'node:test';
import { playNotice } from './store_handlers';
import { playOneTime, playSubscription } from './play_purchase';

const now = Date.parse('2026-10-06T12:00:00Z');

test('an active Play subscription stays on until expiry', () => {
  const parsed = playSubscription(
    {
      subscriptionState: 'SUBSCRIPTION_STATE_CANCELED',
      lineItems: [{ productId: 'field_guide_yearly', expiryTime: '2027-10-06T12:00:00Z' }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: 'token-1' },
    },
    now,
  );
  assert.equal(parsed?.revoked, false);
  assert.equal(parsed?.productId, 'field_guide_yearly');
  assert.equal(parsed?.obfuscatedAccountId, 'token-1');
});

test('a held or expired Play subscription does not grant', () => {
  assert.equal(
    playSubscription(
      {
        subscriptionState: 'SUBSCRIPTION_STATE_ON_HOLD',
        lineItems: [{ productId: 'field_guide_monthly', expiryTime: '2027-01-01T00:00:00Z' }],
      },
      now,
    )?.revoked,
    true,
  );
  assert.equal(
    playSubscription(
      {
        subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
        lineItems: [{ productId: 'field_guide_monthly', expiryTime: '2026-10-01T00:00:00Z' }],
      },
      now,
    )?.revoked,
    true,
  );
});

test('a canceled one-time Play product does not grant, and a license test does', () => {
  assert.equal(playOneTime({ purchaseState: 0, obfuscatedExternalAccountId: 'abc' }, 'no_ads')?.revoked, false);
  assert.equal(playOneTime({ purchaseState: 0, purchaseType: 0 }, 'no_ads')?.revoked, false);
  assert.equal(playOneTime({ purchaseState: 0, testPurchase: {} }, 'no_ads')?.revoked, false);
  assert.equal(playOneTime({ purchaseState: 1, purchaseType: 0 }, 'offline')?.revoked, true);
  assert.equal(playOneTime({ purchaseState: 2 }, 'offline'), null);
});

test('a license-test Play subscription grants while it is active', () => {
  const yearly = {
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    lineItems: [{ productId: 'field_guide_yearly', expiryTime: '2027-10-06T12:00:00Z' }],
  };
  assert.equal(playSubscription(yearly, now)?.revoked, false);
  assert.equal(playSubscription({ ...yearly, testPurchase: {} }, now)?.revoked, false);
  assert.equal(playSubscription({ ...yearly, purchaseType: 0 }, now)?.revoked, false);
  assert.equal(
    playSubscription(
      {
        subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
        testPurchase: {},
        lineItems: [{ productId: 'field_guide_monthly', expiryTime: '2026-10-01T00:00:00Z' }],
      },
      now,
    )?.revoked,
    true,
  );
});

test('a Play notification keeps the purchase token', () => {
  const data = Buffer.from(
    JSON.stringify({
      packageName: 'sk.ab.herbs',
      subscriptionNotification: {
        notificationType: 2,
        purchaseToken: 'token-1',
        subscriptionId: 'field_guide_yearly',
      },
    }),
  ).toString('base64');
  assert.deepEqual(playNotice({ message: { data } }), {
    kind: 'subscription',
    token: 'token-1',
    productId: 'field_guide_yearly',
  });
  const bare = Buffer.from(
    JSON.stringify({
      packageName: 'sk.ab.herbs',
      subscriptionNotification: { notificationType: 13, purchaseToken: 'token-22' },
    }),
  ).toString('base64');
  assert.deepEqual(playNotice({ message: { data: bare } }), {
    kind: 'subscription',
    token: 'token-22',
    productId: '',
  });
  assert.equal(playNotice({ message: { data: Buffer.from('{"packageName":"other"}').toString('base64') } }), null);
});
