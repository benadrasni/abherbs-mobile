import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  activeEntitlementIds,
  hasUnlimitedNames,
  planGrant,
  productsFromWrites,
  purchaseActive,
  type EntitlementRow,
  type VerifiedPurchase,
} from './entitlements';
import { grantPurchase, releaseStorePurchases, type EntitlementDb } from './store_handlers';
import { storeAccountToken } from './store_account';

const now = Date.parse('2026-10-06T12:00:00Z');
const uid = 'user-1';
const token = storeAccountToken(uid);

function yearly(overrides: Partial<VerifiedPurchase> = {}): VerifiedPurchase {
  return {
    store: 'app_store',
    productId: 'field_guide_yearly',
    token: '1000',
    expiresAt: now + 86_400_000,
    revoked: false,
    accountToken: token,
    environment: 'Production',
    subscription: true,
    ...overrides,
  };
}

test('a future expiry is active and a revocation is not', () => {
  assert.equal(purchaseActive({ revoked: false, expiresAt: now + 1 }, now), true);
  assert.equal(purchaseActive({ revoked: false, expiresAt: now }, now), false);
  assert.equal(purchaseActive({ revoked: true, expiresAt: now + 1 }, now), false);
  assert.equal(purchaseActive({ revoked: false, expiresAt: null }, now), true);
});

test('a checked subscription is written on the account and the other plan is cleared', () => {
  const monthly: EntitlementRow = {
    active: true,
    store: 'app_store',
    originalId: 'app_store_1000',
    updatedAt: now - 1,
  };
  const plan = planGrant({
    uid,
    now,
    purchase: yearly(),
    existing: null,
    previousOwnerExists: false,
    products: { field_guide_monthly: monthly },
  });
  assert.equal('error' in plan, false);
  if ('error' in plan) return;
  const products = productsFromWrites(plan.writes);
  assert.equal(products.field_guide_yearly, true);
  assert.equal(products.field_guide_monthly, false);
  assert.equal(plan.writes.some((write) => write.path === `store_accounts/${token}`), true);
});

test('a receipt named for another account is refused until that account is gone', () => {
  const foreign = storeAccountToken('user-2');
  const refused = planGrant({
    uid,
    now,
    purchase: yearly({ accountToken: foreign }),
    existing: null,
    previousOwnerExists: false,
    products: {},
  });
  assert.deepEqual(refused, { error: 'other-account' });

  const expired = planGrant({
    uid,
    now,
    purchase: yearly({ accountToken: foreign, expiresAt: now - 1 }),
    existing: {
      uid,
      store: 'app_store',
      productId: 'field_guide_yearly',
      token: '1000',
      accountToken: token,
      expiresAt: now + 1,
      environment: 'Production',
      subscription: true,
      active: true,
      updatedAt: now,
    },
    previousOwnerExists: false,
    products: {
      field_guide_yearly: {
        active: true,
        store: 'app_store',
        originalId: 'app_store_1000',
        updatedAt: now,
      },
    },
  });
  assert.equal('error' in expired, false);
  if ('error' in expired) return;
  assert.equal(productsFromWrites(expired.writes).field_guide_yearly, false);
  assert.equal(expired.writes.some((write) => write.path.startsWith('store_accounts/')), false);

  const rebound = planGrant({
    uid: 'user-2',
    now,
    purchase: yearly({ accountToken: token }),
    existing: {
      uid,
      store: 'app_store',
      productId: 'field_guide_yearly',
      token: '1000',
      accountToken: token,
      expiresAt: now + 1,
      environment: 'Production',
      subscription: true,
      active: true,
      updatedAt: now,
    },
    previousOwnerExists: false,
    products: {},
  });
  assert.equal('error' in rebound, false);
  if ('error' in rebound) return;
  assert.equal(productsFromWrites(rebound.writes).field_guide_yearly, true);
  assert.equal(
    rebound.writes.some((write) => write.path === `users/${uid}/entitlements/products/field_guide_yearly` && write.value == null),
    true,
  );
});

test('a receipt owned by a live account is refused', () => {
  const plan = planGrant({
    uid: 'user-2',
    now,
    purchase: yearly({ accountToken: storeAccountToken('user-2') }),
    existing: {
      uid,
      store: 'app_store',
      productId: 'field_guide_yearly',
      token: '1000',
      accountToken: token,
      expiresAt: now + 1,
      environment: 'Production',
      subscription: true,
      active: true,
      updatedAt: now,
    },
    previousOwnerExists: true,
    products: {},
  });
  assert.deepEqual(plan, { error: 'other-account' });
});

test('an expired receipt does not clear a different purchase of the same product', () => {
  const plan = planGrant({
    uid,
    now,
    purchase: yearly({ token: '2000', expiresAt: now - 1, accountToken: token }),
    existing: null,
    previousOwnerExists: false,
    products: {
      field_guide_yearly: {
        active: true,
        store: 'play',
        originalId: 'play_other',
        updatedAt: now,
      },
    },
  });
  assert.equal('error' in plan, false);
  if ('error' in plan) return;
  assert.equal(productsFromWrites(plan.writes).field_guide_yearly, undefined);
});

function putPath(root: Record<string, unknown>, path: string, value: unknown): void {
  const parts = path.split('/');
  let cursor = root;
  for (const part of parts.slice(0, -1)) {
    const next = cursor[part];
    if (!next || typeof next !== 'object') cursor[part] = {};
    cursor = cursor[part] as Record<string, unknown>;
  }
  cursor[parts[parts.length - 1]] = value;
}

test('a subscription counts only while expiresAt is ahead', () => {
  const row = (expiresAt?: number, active = true): EntitlementRow => ({
    active,
    ...(expiresAt == null ? {} : { expiresAt }),
    store: 'app_store',
    originalId: 'app_store_1000',
    updatedAt: now,
  });
  const user = (id: string, value: EntitlementRow) => ({
    entitlements: { products: { [id]: value } },
  });
  assert.deepEqual(activeEntitlementIds(user('field_guide_yearly', row(now + 1)), now), ['field_guide_yearly']);
  assert.deepEqual(activeEntitlementIds(user('field_guide_yearly', row(now)), now), []);
  assert.deepEqual(activeEntitlementIds(user('field_guide_yearly', row(now - 1)), now), []);
  assert.deepEqual(activeEntitlementIds(user('field_guide_yearly', row()), now), ['field_guide_yearly']);
  assert.deepEqual(activeEntitlementIds(user('field_guide_yearly', row(now + 1, false)), now), []);
  assert.equal(hasUnlimitedNames(user('field_guide_yearly', row(now - 1)), now), false);
  assert.equal(hasUnlimitedNames(user('field_guide_yearly', row(now + 1)), now), true);
  assert.equal(hasUnlimitedNames(user('search_by_photo', row(now - 1)), now), true);
});

function memoryDb(live: (id: string) => boolean = (id) => id === uid): EntitlementDb & { tree: Record<string, unknown> } {
  const tree: Record<string, unknown> = {};
  const read = (path: string): unknown => {
    let cursor: unknown = tree;
    for (const part of path.split('/')) {
      if (!cursor || typeof cursor !== 'object' || !(part in cursor)) return null;
      cursor = (cursor as Record<string, unknown>)[part];
    }
    return cursor ?? null;
  };
  return {
    tree,
    async get(path) {
      return read(path);
    },
    async set(path, value) {
      putPath(tree, path, value);
    },
    async remove(path) {
      const parts = path.split('/');
      let cursor: unknown = tree;
      for (const part of parts.slice(0, -1)) {
        if (!cursor || typeof cursor !== 'object') return;
        cursor = (cursor as Record<string, unknown>)[part];
      }
      if (cursor && typeof cursor === 'object') {
        delete (cursor as Record<string, unknown>)[parts[parts.length - 1]];
      }
    },
    async transaction(path, update) {
      const stored = read(path);
      // Same order as the Realtime Database client: a cache miss, then the stored row.
      const guessed = update(null);
      if (guessed === undefined) return false;
      if (stored == null) {
        putPath(tree, path, guessed);
        return true;
      }
      const confirmed = update(stored);
      if (confirmed === undefined) return false;
      putPath(tree, path, confirmed);
      return true;
    },
    async authExists(id) {
      return live(id);
    },
  };
}

test('granting then releasing removes the proof and the account record', async () => {
  const db = memoryDb();
  const granted = await grantPurchase(db, uid, yearly(), now);
  assert.equal('products' in granted && granted.products.field_guide_yearly, true);
  const proofs = db.tree.purchase_proofs as Record<string, unknown>;
  assert.ok(proofs.app_store_1000);
  await releaseStorePurchases(db, uid);
  assert.equal(proofs.app_store_1000, undefined);
  const account = (db.tree.users as Record<string, Record<string, unknown>> | undefined)?.[uid];
  assert.equal(account?.entitlements, undefined);
  const accounts = db.tree.store_accounts as Record<string, unknown> | undefined;
  assert.equal(accounts?.[token], undefined);
});

test('a receipt without an account token is claimed by the first live account', async () => {
  const db = memoryDb(() => true);
  const purchase = yearly({ accountToken: null });
  const first = await grantPurchase(db, uid, purchase, now);
  assert.equal('products' in first && first.products.field_guide_yearly, true);
  const again = await grantPurchase(db, uid, purchase, now + 1);
  assert.equal('products' in again && again.products.field_guide_yearly, true);
  const second = await grantPurchase(db, 'user-2', purchase, now);
  assert.deepEqual(second, { error: 'other-account' });
});

test('two concurrent claims of a token-less receipt cannot both win', async () => {
  const db = memoryDb(() => true);
  const purchase = yearly({ accountToken: null });
  const [left, right] = await Promise.all([
    grantPurchase(db, uid, purchase, now),
    grantPurchase(db, 'user-2', purchase, now),
  ]);
  const won = [left, right].filter((result) => 'products' in result);
  const lost = [left, right].filter((result) => 'error' in result);
  assert.equal(won.length, 1);
  assert.equal(lost.length, 1);
  assert.equal('error' in lost[0] && lost[0].error, 'other-account');
  const proofs = db.tree.purchase_proofs as Record<string, { uid: string }>;
  const owner = proofs.app_store_1000.uid;
  const users = db.tree.users as Record<string, { entitlements?: unknown }>;
  assert.ok(users[owner]?.entitlements);
  const other = owner === uid ? 'user-2' : uid;
  assert.equal(users[other]?.entitlements, undefined);
});

test('replaying a pre-refund JWS cannot restore a revoked one-time purchase or subscription', async () => {
  const db = memoryDb();
  const oneTime: VerifiedPurchase = {
    store: 'app_store',
    productId: 'search_by_photo',
    token: '3000',
    expiresAt: null,
    revoked: false,
    signedDate: now - 10_000,
    accountToken: token,
    environment: 'Production',
    subscription: false,
  };
  const granted = await grantPurchase(db, uid, oneTime, now);
  assert.equal('products' in granted && granted.products.search_by_photo, true);

  const refunded = await grantPurchase(
    db,
    uid,
    { ...oneTime, revoked: true, signedDate: now },
    now,
  );
  assert.equal('products' in refunded && refunded.products.search_by_photo, false);

  // Replay of the pre-refund JWS (older signedDate) is rejected.
  const replayed = await grantPurchase(db, uid, oneTime, now + 1000);
  assert.deepEqual(replayed, { error: 'invalid' });

  // Even a replay with no signedDate cannot un-revoke a one-time purchase.
  const replayedNoDate = await grantPurchase(
    db,
    uid,
    { ...oneTime, signedDate: null },
    now + 2000,
  );
  assert.deepEqual(replayedNoDate, { error: 'invalid' });

  // Subscription: replay of pre-refund JWS is rejected, but a newer renewal succeeds.
  const subFirst = yearly({ token: '4000', signedDate: now - 10_000 });
  assert.equal('products' in (await grantPurchase(db, uid, subFirst, now)), true);
  assert.equal(
    'products' in (await grantPurchase(db, uid, { ...subFirst, revoked: true, signedDate: now }, now)),
    true,
  );
  assert.deepEqual(await grantPurchase(db, uid, subFirst, now + 1000), { error: 'invalid' });

  const renewed = await grantPurchase(
    db,
    uid,
    { ...subFirst, signedDate: now + 5000, expiresAt: now + 172_800_000 },
    now + 5000,
  );
  assert.equal('products' in renewed && renewed.products.field_guide_yearly, true);
});
