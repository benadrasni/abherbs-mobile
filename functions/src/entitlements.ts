import { createHash } from 'node:crypto';
import { storeAccountToken } from './store_account';

export const subscriptionProducts = new Set([
  'store_photos_monthly',
  'store_photos_yearly',
  'field_guide_monthly',
  'field_guide_yearly',
]);

export const catalogProducts = new Set([
  'no_ads',
  'NoAds',
  'search',
  'custom_filter',
  'offline',
  'observations',
  'search_by_photo',
  ...subscriptionProducts,
]);

const unlimitedProducts = [
  'search_by_photo',
  'store_photos_monthly',
  'store_photos_yearly',
  'field_guide_monthly',
  'field_guide_yearly',
];

export type StoreName = 'app_store' | 'play';

export type VerifiedPurchase = {
  store: StoreName;
  productId: string;
  /** Apple original transaction id, or the Play purchase token. */
  token: string;
  expiresAt: number | null;
  revoked: boolean;
  signedDate?: number | null;
  accountToken: string | null;
  environment: string | null;
  subscription: boolean;
};

export type EntitlementRow = {
  active: boolean;
  expiresAt?: number;
  store: StoreName;
  originalId: string;
  updatedAt: number;
};

export type ProofRecord = {
  uid: string;
  store: StoreName;
  productId: string;
  token: string;
  accountToken: string | null;
  expiresAt: number | null;
  environment: string | null;
  subscription: boolean;
  active: boolean;
  revoked?: boolean;
  signedDate?: number | null;
  updatedAt: number;
};

export type StoreWrite = { path: string; value: unknown | null };

export function purchaseActive(purchase: { revoked: boolean; expiresAt: number | null }, now: number): boolean {
  if (purchase.revoked) return false;
  if (purchase.expiresAt == null) return true;
  return purchase.expiresAt > now;
}

export function proofKey(store: StoreName, token: string): string | null {
  if (store === 'app_store') {
    if (!/^[0-9]{1,32}$/.test(token)) return null;
    return `app_store_${token}`;
  }
  if (token.length < 8 || token.length > 4096) return null;
  return `play_${createHash('sha256').update(token).digest('base64url')}`;
}

export function knownPurchase(purchase: VerifiedPurchase): boolean {
  return catalogProducts.has(purchase.productId) && proofKey(purchase.store, purchase.token) !== null;
}

function row(purchase: VerifiedPurchase, key: string, active: boolean, now: number): EntitlementRow {
  const value: EntitlementRow = {
    active,
    store: purchase.store,
    originalId: key,
    updatedAt: now,
  };
  if (purchase.expiresAt != null) value.expiresAt = purchase.expiresAt;
  return value;
}

function proofRecord(
  uid: string,
  purchase: VerifiedPurchase,
  active: boolean,
  now: number,
  previousSignedDate: number | null,
): ProofRecord {
  const record: ProofRecord = {
    uid,
    store: purchase.store,
    productId: purchase.productId,
    token: purchase.token,
    accountToken: purchase.accountToken,
    expiresAt: purchase.expiresAt,
    environment: purchase.environment,
    subscription: purchase.subscription,
    active,
    revoked: purchase.revoked,
    updatedAt: now,
  };
  const signedDate = purchase.signedDate ?? previousSignedDate;
  if (signedDate != null) record.signedDate = signedDate;
  return record;
}

/**
 * Writes for a receipt this user just submitted. A receipt already bound to
 * a live account is refused. A receipt whose account was deleted is rebound.
 */
export function planGrant(input: {
  uid: string;
  now: number;
  purchase: VerifiedPurchase;
  existing: ProofRecord | null;
  previousOwnerExists: boolean;
  products: Record<string, EntitlementRow>;
}): { error: 'invalid' | 'other-account' } | { writes: StoreWrite[] } {
  const key = proofKey(input.purchase.store, input.purchase.token);
  if (!key || !knownPurchase(input.purchase)) return { error: 'invalid' };
  const existing = input.existing;
  const expectedToken = storeAccountToken(input.uid);
  const accountToken = input.purchase.accountToken;
  const tokenMismatch = Boolean(accountToken) && accountToken !== expectedToken;
  if (tokenMismatch) {
    const sameOwner = existing != null && existing.uid === input.uid;
    const releasedOwner =
      existing != null && existing.uid !== input.uid && !input.previousOwnerExists;
    if (!sameOwner && !releasedOwner) return { error: 'other-account' };
  }
  if (existing && existing.uid !== input.uid && input.previousOwnerExists) {
    return { error: 'other-account' };
  }
  if (existing && existing.store === input.purchase.store) {
    if (
      existing.signedDate != null &&
      input.purchase.signedDate != null &&
      input.purchase.signedDate < existing.signedDate
    ) {
      return { error: 'invalid' };
    }
    if (existing.revoked === true && !input.purchase.revoked) {
      if (!input.purchase.subscription) {
        return { error: 'invalid' };
      }
      const newerSigned =
        existing.signedDate != null &&
        input.purchase.signedDate != null &&
        input.purchase.signedDate > existing.signedDate;
      const laterExpiry =
        input.purchase.expiresAt != null &&
        (existing.expiresAt == null || input.purchase.expiresAt > existing.expiresAt);
      if (!newerSigned && !laterExpiry) {
        return { error: 'invalid' };
      }
    }
  }
  const active = purchaseActive(input.purchase, input.now);
  const current = input.products[input.purchase.productId];
  const heldByOther =
    !active &&
    current?.active === true &&
    current.originalId !== key;
  const previousSignedDate =
    existing && existing.store === input.purchase.store ? existing.signedDate ?? null : null;
  const writes: StoreWrite[] = [
    {
      path: `purchase_proofs/${key}`,
      value: proofRecord(input.uid, input.purchase, active, input.now, previousSignedDate),
    },
    {
      path: `users/${input.uid}/proof_keys/${key}`,
      value: true,
    },
  ];
  if (existing && existing.uid !== input.uid) {
    writes.push({
      path: `users/${existing.uid}/entitlements/products/${existing.productId}`,
      value: null,
    });
    writes.push({
      path: `users/${existing.uid}/proof_keys/${key}`,
      value: null,
    });
  }
  for (const [productId, owned] of Object.entries(input.products)) {
    if (owned.originalId === key && productId !== input.purchase.productId) {
      writes.push({
        path: `users/${input.uid}/entitlements/products/${productId}`,
        value: { ...owned, active: false, updatedAt: input.now },
      });
    }
  }
  if (!heldByOther) {
    writes.push({
      path: `users/${input.uid}/entitlements/products/${input.purchase.productId}`,
      value: row(input.purchase, key, active, input.now),
    });
  }
  writes.push({ path: `users/${input.uid}/entitlements/updatedAt`, value: input.now });
  if (accountToken && accountToken === expectedToken && /^[0-9a-f-]{36}$/i.test(accountToken)) {
    writes.push({ path: `store_accounts/${accountToken}`, value: input.uid });
  }
  return { writes };
}

export function notificationUid(input: {
  proof: ProofRecord | null;
  accountUid: string | null;
  proofOwnerExists: boolean;
  accountOwnerExists: boolean;
}): string | null {
  if (input.proof) return input.proofOwnerExists ? input.proof.uid : null;
  if (input.accountUid && input.accountOwnerExists) return input.accountUid;
  return null;
}

export function productsFromWrites(writes: StoreWrite[]): Record<string, boolean> {
  const products: Record<string, boolean> = {};
  for (const write of writes) {
    const match = write.path.match(/^users\/[^/]+\/entitlements\/products\/([^/]+)$/);
    if (!match) continue;
    if (write.value && typeof write.value === 'object' && 'active' in write.value) {
      products[match[1]] = (write.value as EntitlementRow).active === true;
    } else if (write.value == null) {
      products[match[1]] = false;
    }
  }
  return products;
}

export function entitlementRows(value: unknown): Record<string, EntitlementRow> {
  if (!value || typeof value !== 'object') return {};
  const products = (value as { products?: unknown }).products;
  if (!products || typeof products !== 'object') return {};
  const rows: Record<string, EntitlementRow> = {};
  for (const [id, rowValue] of Object.entries(products)) {
    if (!rowValue || typeof rowValue !== 'object') continue;
    const record = rowValue as Partial<EntitlementRow>;
    if (typeof record.originalId !== 'string' || (record.store !== 'app_store' && record.store !== 'play')) {
      continue;
    }
    rows[id] = {
      active: record.active === true,
      expiresAt: typeof record.expiresAt === 'number' ? record.expiresAt : undefined,
      store: record.store,
      originalId: record.originalId,
      updatedAt: typeof record.updatedAt === 'number' ? record.updatedAt : 0,
    };
  }
  return rows;
}

export function proofRecordOf(value: unknown): ProofRecord | null {
  if (!value || typeof value !== 'object') return null;
  const record = value as Partial<ProofRecord>;
  if (typeof record.uid !== 'string' || typeof record.productId !== 'string' || typeof record.token !== 'string') {
    return null;
  }
  if (record.store !== 'app_store' && record.store !== 'play') return null;
  const result: ProofRecord = {
    uid: record.uid,
    store: record.store,
    productId: record.productId,
    token: record.token,
    accountToken: typeof record.accountToken === 'string' ? record.accountToken : null,
    expiresAt: typeof record.expiresAt === 'number' ? record.expiresAt : null,
    environment: typeof record.environment === 'string' ? record.environment : null,
    subscription: record.subscription === true,
    active: record.active === true,
    revoked: record.revoked === true,
    updatedAt: typeof record.updatedAt === 'number' ? record.updatedAt : 0,
  };
  if (typeof record.signedDate === 'number' && Number.isFinite(record.signedDate)) {
    result.signedDate = record.signedDate;
  }
  return result;
}

function rowStillActive(id: string, row: EntitlementRow, now: number): boolean {
  if (!row.active) return false;
  if (!subscriptionProducts.has(id) || row.expiresAt == null) return true;
  return purchaseActive({ revoked: false, expiresAt: row.expiresAt }, now);
}

/// Product ids the server has checked and still considers active.
/// A subscription with expiresAt counts only while that time is still ahead.
/// A missing expiresAt stays on the active flag, same as purchaseActive.
export function activeEntitlementIds(user: Record<string, unknown> | null, now = Date.now()): string[] {
  if (!user) return [];
  return Object.entries(entitlementRows(user.entitlements))
    .filter(([id, row]) => rowStillActive(id, row, now))
    .map(([id]) => id);
}

/**
 * Unlimited photo names. `old version` is server-set. A checked entitlement
 * grants the same. The client-written `purchases` list is not an entitlement.
 */
export function hasUnlimitedNames(user: Record<string, unknown> | null, now = Date.now()): boolean {
  if (!user) return false;
  if (user['old version'] === true) return true;
  return activeEntitlementIds(user, now).some((id) => unlimitedProducts.includes(id));
}
