import {
  appleTransaction,
  appStoreBundleId,
  verifyAppleSignedPayload,
  type AppleTransaction,
} from './apple_jws';
import {
  entitlementRows,
  notificationUid,
  planGrant,
  productsFromWrites,
  proofKey,
  proofRecordOf,
  type ProofRecord,
  type VerifiedPurchase,
} from './entitlements';
import { playPackageName } from './play_purchase';
import { storeAccountToken } from './store_account';

export type EntitlementDb = {
  get(path: string): Promise<unknown>;
  set(path: string, value: unknown): Promise<void>;
  remove(path: string): Promise<void>;
  /// Return undefined from update to leave the row unchanged.
  transaction(path: string, update: (current: unknown) => unknown): Promise<boolean>;
  authExists(uid: string): Promise<boolean>;
};

async function applyWrites(
  db: EntitlementDb,
  writes: { path: string; value: unknown | null }[],
): Promise<void> {
  for (const write of writes) {
    if (write.value == null) await db.remove(write.path);
    else await db.set(write.path, write.value);
  }
}

function sameStoredProof(current: unknown, expected: ProofRecord | null): boolean {
  if (expected == null) return current == null;
  const proof = proofRecordOf(current);
  return proof != null && JSON.stringify(proof) === JSON.stringify(expected);
}

/// Claims the receipt inside a transaction, then writes the account rows.
/// A receipt with no account token can still be taken by the first live account.
export async function grantPurchase(
  db: EntitlementDb,
  uid: string,
  purchase: VerifiedPurchase,
  now: number,
): Promise<{ error: 'invalid' | 'other-account' } | { products: Record<string, boolean> }> {
  const key = proofKey(purchase.store, purchase.token);
  if (!key) return { error: 'invalid' };
  const proofPath = `purchase_proofs/${key}`;
  for (let attempt = 0; attempt < 4; attempt++) {
    const existing = proofRecordOf(await db.get(proofPath));
    const previousOwnerExists =
      existing != null && existing.uid !== uid ? await db.authExists(existing.uid) : false;
    const products = entitlementRows(await db.get(`users/${uid}/entitlements`));
    const plan = planGrant({ uid, now, purchase, existing, previousOwnerExists, products });
    if ('error' in plan) return plan;
    const proofWrite = plan.writes.find((write) => write.path === proofPath);
    if (!proofWrite || proofWrite.value == null) return { error: 'invalid' };
    const proofValue = proofWrite.value;
    const committed = await db.transaction(proofPath, (current) => {
      if (sameStoredProof(current, existing)) return proofValue;
      // get() does not keep the row cached, so this often runs once with null
      // and then again with the stored row. A different stored row aborts.
      if (current == null) return proofValue;
      return undefined;
    });
    if (!committed) continue;
    await applyWrites(
      db,
      plan.writes.filter((write) => write.path !== proofPath),
    );
    return { products: productsFromWrites(plan.writes) };
  }
  return { error: 'other-account' };
}

export async function applyVerifiedNotification(
  db: EntitlementDb,
  purchase: VerifiedPurchase,
  now: number,
): Promise<boolean> {
  const key = proofKey(purchase.store, purchase.token);
  if (!key) return false;
  const proof = proofRecordOf(await db.get(`purchase_proofs/${key}`));
  let accountUid: string | null = null;
  if (purchase.accountToken && /^[0-9a-f-]{36}$/i.test(purchase.accountToken)) {
    const mapped = await db.get(`store_accounts/${purchase.accountToken}`);
    if (typeof mapped === 'string') accountUid = mapped;
  }
  const uid = notificationUid({
    proof,
    accountUid,
    proofOwnerExists: proof ? await db.authExists(proof.uid) : false,
    accountOwnerExists: accountUid ? await db.authExists(accountUid) : false,
  });
  if (!uid) return false;
  const result = await grantPurchase(db, uid, purchase, now);
  return !('error' in result);
}

export async function registerStoreAccount(db: EntitlementDb, uid: string): Promise<void> {
  const token = storeAccountToken(uid);
  const current = await db.get(`store_accounts/${token}`);
  if (current == null) await db.set(`store_accounts/${token}`, uid);
}

export async function releaseStorePurchases(db: EntitlementDb, uid: string): Promise<void> {
  const keys = new Set<string>();
  const indexed = await db.get(`users/${uid}/proof_keys`);
  if (indexed && typeof indexed === 'object') {
    for (const key of Object.keys(indexed as Record<string, unknown>)) {
      if (/^[A-Za-z0-9_-]{1,128}$/.test(key)) keys.add(key);
    }
  }
  const entitlements = entitlementRows(await db.get(`users/${uid}/entitlements`));
  for (const row of Object.values(entitlements)) {
    if (/^[A-Za-z0-9_-]{1,128}$/.test(row.originalId)) keys.add(row.originalId);
  }
  const now = Date.now();
  for (const key of keys) {
    const proof = proofRecordOf(await db.get(`purchase_proofs/${key}`));
    if (!proof || proof.uid !== uid) continue;
    // Keep the proof row (inactive) so planGrant can still match previousOwnerExists
    // when this user deletes their account and restores a tokened purchase on a new one.
    await db.set(`purchase_proofs/${key}`, { ...proof, active: false, updatedAt: now });
  }
  await db.remove(`users/${uid}/proof_keys`);
  await db.remove(`users/${uid}/entitlements`);
  await db.remove(`store_accounts/${storeAccountToken(uid)}`);
}

const subscriptionRefreshGraceMs = 7 * 24 * 60 * 60 * 1000;

export async function subscriptionProofs(db: EntitlementDb, now = Date.now()): Promise<ProofRecord[]> {
  const all = await db.get('purchase_proofs');
  if (!all || typeof all !== 'object') return [];
  const proofs: ProofRecord[] = [];
  for (const value of Object.values(all as Record<string, unknown>)) {
    const proof = proofRecordOf(value);
    if (!proof?.subscription) continue;
    const withinGrace =
      proof.expiresAt == null || proof.expiresAt + subscriptionRefreshGraceMs > now;
    if (proof.active || (!proof.revoked && withinGrace)) {
      proofs.push(proof);
    }
  }
  return proofs;
}

export type AppleNotice = { kind: 'transaction'; purchase: VerifiedPurchase } | { kind: 'ignore' } | { kind: 'bad' };

export function appleNotice(
  body: unknown,
  now: number,
  toPurchase: (transaction: AppleTransaction) => VerifiedPurchase,
): AppleNotice {
  if (!body || typeof body !== 'object') return { kind: 'bad' };
  const signed = (body as { signedPayload?: unknown }).signedPayload;
  if (typeof signed !== 'string') return { kind: 'bad' };
  const payload = verifyAppleSignedPayload(signed, now);
  if (!payload) return { kind: 'bad' };
  if (payload.notificationType === 'TEST') return { kind: 'ignore' };
  const data = payload.data;
  if (!data || typeof data !== 'object') return { kind: 'ignore' };
  if ((data as { bundleId?: unknown }).bundleId !== appStoreBundleId) return { kind: 'ignore' };
  const signedTransaction = (data as { signedTransactionInfo?: unknown }).signedTransactionInfo;
  if (typeof signedTransaction !== 'string') return { kind: 'ignore' };
  const transactionPayload = verifyAppleSignedPayload(signedTransaction, now);
  if (!transactionPayload) return { kind: 'bad' };
  const transaction = appleTransaction(transactionPayload);
  const purchase = transaction ? toPurchase(transaction) : null;
  if (!purchase) return { kind: 'ignore' };
  return { kind: 'transaction', purchase };
}

export type PlayNotice =
  | { kind: 'subscription'; token: string; productId: string }
  | { kind: 'product'; token: string; productId: string }
  | { kind: 'voided'; token: string };

export function playNotice(body: unknown): PlayNotice | null {
  if (!body || typeof body !== 'object') return null;
  const data = (body as { message?: { data?: unknown } }).message?.data;
  if (typeof data !== 'string' || data.length === 0) return null;
  let decoded: unknown;
  try {
    decoded = JSON.parse(Buffer.from(data, 'base64').toString('utf8'));
  } catch {
    return null;
  }
  if (!decoded || typeof decoded !== 'object') return null;
  const record = decoded as Record<string, unknown>;
  if (record.packageName !== playPackageName) return null;
  const subscription = record.subscriptionNotification;
  if (subscription && typeof subscription === 'object') {
    const token = (subscription as { purchaseToken?: unknown }).purchaseToken;
    const productId = (subscription as { subscriptionId?: unknown }).subscriptionId;
    // Current Play notices carry the token only. subscriptionsv2 names the product.
    if (typeof token === 'string' && token.length > 0) {
      return {
        kind: 'subscription',
        token,
        productId: typeof productId === 'string' ? productId : '',
      };
    }
  }
  const product = record.oneTimeProductNotification;
  if (product && typeof product === 'object') {
    const token = (product as { purchaseToken?: unknown }).purchaseToken;
    const productId = (product as { sku?: unknown }).sku;
    if (typeof token === 'string' && typeof productId === 'string') {
      return { kind: 'product', token, productId };
    }
  }
  const voided = record.voidedPurchaseNotification;
  if (voided && typeof voided === 'object') {
    const token = (voided as { purchaseToken?: unknown }).purchaseToken;
    if (typeof token === 'string') return { kind: 'voided', token };
  }
  return null;
}
