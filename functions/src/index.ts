import { createHash } from 'node:crypto';
import { getAuth } from 'firebase-admin/auth';
import { initializeApp } from 'firebase-admin/app';
import { getDatabase, type Reference } from 'firebase-admin/database';
import { logger } from 'firebase-functions';
import { defineBoolean, defineInt, defineSecret, defineString } from 'firebase-functions/params';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { appleTransaction, verifyAppleSignedPayload } from './apple_jws';
import {
  catalogProducts,
  proofKey,
  proofRecordOf,
  subscriptionProducts,
  type VerifiedPurchase,
} from './entitlements';
import {
  appleNotice,
  applyVerifiedNotification,
  grantPurchase,
  registerStoreAccount as registerAccount,
  releaseStorePurchases as releaseAccount,
  subscriptionProofs,
  playNotice,
  type EntitlementDb,
} from './store_handlers';
import {
  fetchAppleSubscription,
  fetchAppleTransaction,
  fetchPlayPurchase,
  playBearer,
  playCredentialsOf,
  StoreUnavailable,
  verifiedApple,
  type AppStoreCredentials,
} from './store_fetch';
import { verifyAdmobCallback } from './admob';
import {
  hasUnlimitedNames,
  isPlant,
  meterCounts,
  releaseAnonymousFree,
  releaseName,
  rememberPhoto,
  reserveCall,
  takeAdGrant,
  takeAnonymousFree,
  takeFreeNotPlant,
  takeName,
  takeSharedSlot,
  utcDay,
  utcMonth,
  type QuotaState,
  type Refusal,
} from './quota';
import {
  plantIdBody,
  plantIdFinished,
  plantIdLanguage,
  plantIdSuggestions,
  plantIdUrl,
  suggestionsForPlants,
} from './plantid';
import {
  leadingScientificName,
  nameOutsideBook,
  nextNameTally,
  photoLookupKey,
  photoNameTallyPath,
} from './tally';

initializeApp();

const plantIdKey = defineSecret('PLANT_ID_KEY');
const playPublisherJson = defineSecret('PLAY_PUBLISHER_JSON');
const appStoreIssuerId = defineSecret('APP_STORE_ISSUER_ID');
const appStoreKeyId = defineSecret('APP_STORE_KEY_ID');
const appStorePrivateKey = defineSecret('APP_STORE_PRIVATE_KEY');
const isPlantThresholdPercent = defineInt('IS_PLANT_THRESHOLD_PERCENT', { default: 50 });
const freeNotPlantPerMonth = defineInt('FREE_NOT_PLANT_PER_MONTH', { default: 3 });
const dailyCeilingFree = defineInt('DAILY_CEILING_FREE', { default: 15 });
const dailyCeilingUnlimited = defineInt('DAILY_CEILING_UNLIMITED', { default: 30 });
const adGrantsPerMonth = defineInt('AD_GRANTS_PER_MONTH', { default: 5 });
const anonymousLifetimeCalls = defineInt('ANONYMOUS_LIFETIME_CALLS', { default: 3 });
const anonymousDailyCeiling = defineInt('ANONYMOUS_DAILY_CEILING', { default: 300 });
const allowAppleSandbox = defineBoolean('ALLOW_APPLE_SANDBOX', { default: false });
const admobRewardedAdUnits = defineString('ADMOB_REWARDED_AD_UNITS', { default: '' });

const maxImageChars = 8 * 1024 * 1024;
const cooldownMs = 5_000;
const repeatWindowMs = 24 * 60 * 60 * 1000;

const firebaseKey = /^[^.#$[\]/]{1,128}$/;

function logCredit(uid: string, feature: string): Promise<void> {
  return getDatabase().ref(`credits/${uid}/${Date.now()}`).set(feature);
}

async function addCredit(uid: string, feature: string): Promise<void> {
  await getDatabase()
    .ref(`users/${uid}/credits`)
    .transaction((current) => (typeof current === 'number' ? current : 0) + 1);
  await logCredit(uid, feature);
}

async function updateQuota<T>(
  ref: Reference,
  step: (current: QuotaState | null) => { state: QuotaState; value: T },
): Promise<T> {
  let value: T | undefined;
  const result = await ref.transaction((current: QuotaState | null) => {
    const next = step(current);
    value = next.value;
    return next.state;
  });
  if (!result.committed) {
    throw new HttpsError('aborted', 'quota-contention');
  }
  return value as T;
}

export const identifyPlant = onCall(
  {
    secrets: [plantIdKey],
    enforceAppCheck: true,
    memory: '512MiB',
    timeoutSeconds: 60,
    maxInstances: 10,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'sign-in');
    const image = request.data?.image;
    if (typeof image !== 'string' || image.length === 0 || image.length > maxImageChars) {
      throw new HttpsError('invalid-argument', 'image');
    }
    const rawLanguage = request.data?.language;
    const language =
      typeof rawLanguage === 'string' && /^[a-z]{2,3}(?:[-_][A-Za-z]{2,4}){0,2}$/.test(rawLanguage)
        ? rawLanguage
        : 'en';

    const db = getDatabase();
    const anonymous = request.auth?.token.firebase?.sign_in_provider === 'anonymous';
    const user = anonymous ? null : (await db.ref(`users/${uid}`).get()).val();
    const unlimited = hasUnlimitedNames(user);
    const hash = createHash('sha256').update(image).digest('base64url');
    const quotaRef = db.ref(`photo_quota/${uid}`);

    const reservation = await updateQuota<{ refusal?: Refusal | 'no-names'; held: boolean }>(quotaRef, (current) => {
      const now = Date.now();
      const reserved = reserveCall(current, now, hash, {
        dailyCeiling: unlimited ? dailyCeilingUnlimited.value() : dailyCeilingFree.value(),
        cooldownMs,
        repeatWindowMs,
        lifetimeCeiling: anonymous ? anonymousLifetimeCalls.value() : undefined,
      });
      if ('refusal' in reserved) {
        return { state: current ?? {}, value: { refusal: reserved.refusal, held: false } };
      }
      if (anonymous) {
        const taken = takeAnonymousFree(reserved.state);
        if (!taken.free) {
          return { state: current ?? {}, value: { refusal: 'sign-in', held: false } };
        }
        return { state: taken.state, value: { held: false } };
      }
      if (!unlimited) {
        const taken = takeName(reserved.state, now);
        if (!taken.taken) {
          return { state: current ?? {}, value: { refusal: 'no-names', held: false } };
        }
        return { state: taken.state, value: { held: true } };
      }
      return { state: reserved.state, value: { held: false } };
    });
    if (reservation.refusal) {
      throw new HttpsError('resource-exhausted', reservation.refusal, { reason: reservation.refusal });
    }

    const releaseFree = () =>
      quotaRef.transaction((current: QuotaState | null) => releaseAnonymousFree(current));
    if (anonymous) {
      let slot = false;
      const shared = await db.ref(`anonymous_daily/${utcDay(Date.now())}`).transaction((current) => {
        const taken = takeSharedSlot(current, anonymousDailyCeiling.value());
        slot = taken.taken;
        if (!taken.taken) return;
        return taken.value;
      });
      if (!shared.committed || !slot) {
        await releaseFree();
        throw new HttpsError('resource-exhausted', 'sign-in', { reason: 'sign-in' });
      }
    }

    const held = reservation.held;

    let body: Record<string, unknown>;
    try {
      const response = await fetch(plantIdUrl(plantIdLanguage(language)), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Api-Key': plantIdKey.value() },
        body: JSON.stringify(plantIdBody(image)),
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        const detail = (await response.text()).slice(0, 300);
        throw new Error(`Plant.id ${response.status} ${detail}`);
      }
      body = (await response.json()) as Record<string, unknown>;
      if (!plantIdFinished(body)) throw new Error('Plant.id incomplete');
    } catch (error) {
      logger.error('identifyPlant: Plant.id failed', { uid, error: String(error) });
      if (held) {
        await quotaRef.transaction((current: QuotaState | null) => releaseName(current));
      }
      if (anonymous) await releaseFree();
      throw new HttpsError('unavailable', 'identify-failed');
    }

    await quotaRef.transaction((current: QuotaState | null) =>
      rememberPhoto(current, Date.now(), hash),
    );

    const suggestions = isPlant(body, isPlantThresholdPercent.value())
      ? suggestionsForPlants(plantIdSuggestions(body))
      : [];

    let charged = held;
    if (suggestions.length === 0 && held) {
      const free = await updateQuota<boolean>(quotaRef, (current) => {
        const taken = takeFreeNotPlant(current, Date.now(), freeNotPlantPerMonth.value());
        return { state: taken.state, value: taken.free };
      });
      if (free) {
        await quotaRef.transaction((current: QuotaState | null) => releaseName(current));
        charged = false;
      }
    }
    if (anonymous && suggestions.length === 0) await releaseFree();

    try {
      await tallyOutsideName(suggestions);
    } catch (error) {
      logger.error('identifyPlant: name tally failed', { error: String(error) });
    }

    const meter = meterCounts((await quotaRef.get()).val() as QuotaState | null, Date.now());
    return {
      isPlant: suggestions.length > 0,
      charged,
      namesUsed: meter.namesUsed,
      adGrants: meter.adGrants,
      anonymousFreeUsed: anonymous && suggestions.length > 0,
      suggestions,
    };
  },
);

/**
 * Counts the leading Plant.id name when `search_photo` has no catalog path.
 * A species or a higher-taxon list is already in the book. The node is
 * `photo_name_tally/{yyyy-mm}/{key}` with the Latin name and the month's count.
 * No photo, place, or account is stored.
 */
async function tallyOutsideName(suggestions: Record<string, unknown>[]): Promise<void> {
  const name = leadingScientificName(suggestions);
  const key = name === null ? null : photoLookupKey(name);
  if (name === null || key === null) return;
  const db = getDatabase();
  const entry = (await db.ref(`search_photo/${key}`).get()).val();
  if (!nameOutsideBook(entry)) return;
  await db.ref(`${photoNameTallyPath}/${utcMonth(Date.now())}/${key}`).transaction((current) =>
    nextNameTally(current, name),
  );
}

/**
 * AdMob rewarded-ad server-side verification callback. The app sets
 * `ServerSideVerificationOptions(userId: uid)` on the rewarded ad. AdMob
 * retries on anything but 200, so handled duplicates and refusals answer 200.
 */
export const admobReward = onRequest({ maxInstances: 5 }, async (req, res) => {
  const raw = req.originalUrl;
  const query = raw.includes('?') ? raw.slice(raw.indexOf('?') + 1) : '';
  let params: URLSearchParams | null;
  try {
    params = await verifyAdmobCallback(query);
  } catch (error) {
    logger.error('admobReward: key fetch failed', { error: String(error) });
    res.status(503).send('retry');
    return;
  }
  if (!params) {
    res.status(403).send('bad signature');
    return;
  }
  const uid = params.get('user_id') ?? '';
  const transaction = params.get('transaction_id') ?? '';
  const rewardAmount = Number(params.get('reward_amount') ?? '0');
  const allowedUnits = admobRewardedAdUnits
    .value()
    .split(',')
    .map((unit) => unit.trim())
    .filter((unit) => unit.length > 0);
  const adUnit = params.get('ad_unit') ?? '';
  if (
    !firebaseKey.test(uid) ||
    !firebaseKey.test(transaction) ||
    !Number.isFinite(rewardAmount) ||
    rewardAmount <= 0 ||
    (allowedUnits.length > 0 && !allowedUnits.includes(adUnit))
  ) {
    res.status(200).send('ignored');
    return;
  }

  const db = getDatabase();
  let duplicate = false;
  const dedup = await db.ref(`ad_rewards/${transaction}`).transaction((current) => {
    if (current !== null) {
      duplicate = true;
      return;
    }
    duplicate = false;
    return { uid, at: Date.now() };
  });
  if (duplicate) {
    res.status(200).send('duplicate');
    return;
  }
  if (!dedup.committed) {
    res.status(503).send('retry');
    return;
  }

  const granted = await updateQuota<boolean>(db.ref(`photo_quota/${uid}`), (current) => {
    const taken = takeAdGrant(current, Date.now(), adGrantsPerMonth.value());
    return { state: taken.state, value: taken.granted };
  });
  if (granted) await addCredit(uid, '1');
  res.status(200).send(granted ? 'ok' : 'month cap');
});

function entitlementDb(): EntitlementDb {
  const db = getDatabase();
  return {
    get: async (path) => (await db.ref(path).get()).val(),
    set: (path, value) => db.ref(path).set(value),
    remove: (path) => db.ref(path).remove(),
    transaction: async (path, update) => {
      const result = await db.ref(path).transaction((current: unknown) => {
        const next = update(current);
        if (next === undefined) return;
        return next;
      });
      return result.committed;
    },
    authExists: async (uid) => {
      try {
        await getAuth().getUser(uid);
        return true;
      } catch (error) {
        if ((error as { code?: string }).code === 'auth/user-not-found') return false;
        throw error;
      }
    },
  };
}

function signedInUid(uid: string | undefined, provider: string | undefined): string {
  if (!uid || !firebaseKey.test(uid) || provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'sign-in');
  }
  return uid;
}

/**
 * Checks a StoreKit 2 transaction or a Play purchase token and writes
 * `users/{uid}/entitlements`. The client cannot write that node.
 * App Store notifications: `appleStoreNotification`.
 * Play real-time notifications: `playStoreNotification`.
 */
export const submitPurchase = onCall(
  {
    enforceAppCheck: true,
    secrets: [playPublisherJson, appStoreIssuerId, appStoreKeyId, appStorePrivateKey],
  },
  async (request) => {
    const uid = signedInUid(request.auth?.uid, request.auth?.token.firebase?.sign_in_provider);
    const store = request.data?.store;
    const productId = request.data?.productId;
    const proof = request.data?.proof;
    if (
      (store !== 'app_store' && store !== 'google_play') ||
      typeof productId !== 'string' ||
      !catalogProducts.has(productId) ||
      typeof proof !== 'string' ||
      proof.length === 0 ||
      proof.length > 32768
    ) {
      throw new HttpsError('invalid-argument', 'proof');
    }
    const now = Date.now();
    let purchase: VerifiedPurchase | null = null;
    if (store === 'app_store') {
      const payload = verifyAppleSignedPayload(proof, now);
      const transaction = payload ? appleTransaction(payload) : null;
      if (!transaction) throw new HttpsError('invalid-argument', 'proof');
      if (transaction.environment === 'Sandbox' && !allowAppleSandbox.value()) {
        throw new HttpsError('invalid-argument', 'sandbox');
      }
      const issuer = appStoreIssuerId.value();
      const keyId = appStoreKeyId.value();
      const privateKey = appStorePrivateKey.value();
      if (!issuer || !keyId || !privateKey) {
        throw new HttpsError('failed-precondition', 'app_store');
      }
      const credentials: AppStoreCredentials = { issuerId: issuer, keyId, privateKey };
      try {
        const fetched = subscriptionProducts.has(transaction.productId)
          ? await fetchAppleSubscription(
              transaction.originalTransactionId,
              transaction.environment,
              credentials,
              now,
              fetch,
            )
          : await fetchAppleTransaction(
              transaction.transactionId ?? transaction.originalTransactionId,
              transaction.environment,
              credentials,
              now,
              fetch,
            );
        purchase = fetched.status === 'verified' ? fetched.purchase : null;
      } catch (error) {
        if (error instanceof StoreUnavailable) throw new HttpsError('unavailable', 'app_store');
        throw error;
      }
      if (purchase?.environment === 'Sandbox' && !allowAppleSandbox.value()) {
        throw new HttpsError('invalid-argument', 'sandbox');
      }
    } else {
      const credentials = playCredentialsOf(playPublisherJson.value());
      if (!credentials) throw new HttpsError('failed-precondition', 'play');
      try {
        const fetched = await fetchPlayPurchase(
          proof,
          productId,
          subscriptionProducts.has(productId),
          credentials,
          now,
          fetch,
        );
        purchase = fetched.status === 'verified' ? fetched.purchase : null;
      } catch (error) {
        if (error instanceof StoreUnavailable) throw new HttpsError('unavailable', 'play');
        throw error;
      }
    }
    if (!purchase) throw new HttpsError('invalid-argument', 'proof');
    const result = await grantPurchase(entitlementDb(), uid, purchase, now);
    if ('error' in result) {
      const code = result.error === 'other-account' ? 'already-exists' : 'invalid-argument';
      throw new HttpsError(code, result.error);
    }
    return { products: result.products };
  },
);

export const registerStoreAccount = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = signedInUid(request.auth?.uid, request.auth?.token.firebase?.sign_in_provider);
  await registerAccount(entitlementDb(), uid);
  return { ok: true };
});

export const releaseStorePurchases = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = signedInUid(request.auth?.uid, request.auth?.token.firebase?.sign_in_provider);
  await releaseAccount(entitlementDb(), uid);
  return { ok: true };
});

export const appleStoreNotification = onRequest({ invoker: 'public' }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('method');
    return;
  }
  const notice = appleNotice(req.body, Date.now(), verifiedApple);
  if (notice.kind === 'bad') {
    res.status(400).send('signature');
    return;
  }
  if (notice.kind === 'ignore') {
    res.status(200).send('ignored');
    return;
  }
  if (notice.purchase.environment === 'Sandbox' && !allowAppleSandbox.value()) {
    res.status(200).send('ignored');
    return;
  }
  try {
    await applyVerifiedNotification(entitlementDb(), notice.purchase, Date.now());
  } catch (error) {
    logger.error('appleStoreNotification', { error: String(error) });
    res.status(503).send('retry');
    return;
  }
  res.status(200).send('ok');
});

export const playStoreNotification = onRequest(
  {
    invoker: 'play-rtdn-push@abherbs-backend.iam.gserviceaccount.com',
    maxInstances: 5,
    secrets: [playPublisherJson],
  },
  async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('method');
    return;
  }
  const notice = playNotice(req.body);
  if (!notice) {
    res.status(200).send('ignored');
    return;
  }
  const credentials = playCredentialsOf(playPublisherJson.value());
  if (!credentials) {
    res.status(503).send('retry');
    return;
  }
  const now = Date.now();
  try {
    const db = entitlementDb();
    if (notice.kind === 'voided') {
      const key = proofKey('play', notice.token);
      const proof = key ? proofRecordOf(await db.get(`purchase_proofs/${key}`)) : null;
      if (!proof) {
        res.status(200).send('ignored');
        return;
      }
      const fetched = await fetchPlayPurchase(
        notice.token,
        proof.productId,
        proof.subscription,
        credentials,
        now,
        fetch,
      );
      const purchase = fetched.status === 'verified' ? fetched.purchase : { ...revokedProof(proof), revoked: true };
      await applyVerifiedNotification(db, purchase, now);
    } else {
      const fetched = await fetchPlayPurchase(
        notice.token,
        notice.productId,
        notice.kind === 'subscription',
        credentials,
        now,
        fetch,
      );
      if (fetched.status === 'verified') await applyVerifiedNotification(db, fetched.purchase, now);
    }
  } catch (error) {
    logger.error('playStoreNotification', { error: String(error) });
    res.status(503).send('retry');
    return;
  }
  res.status(200).send('ok');
});

export const refreshStoreEntitlements = onSchedule(
  {
    schedule: 'every 24 hours',
    timeoutSeconds: 300,
    secrets: [playPublisherJson, appStoreIssuerId, appStoreKeyId, appStorePrivateKey],
  },
  async () => {
    const db = entitlementDb();
    const now = Date.now();
    const proofs = (await subscriptionProofs(db, now)).slice(0, 500);
    const play = playCredentialsOf(playPublisherJson.value());
    const issuer = appStoreIssuerId.value();
    const keyId = appStoreKeyId.value();
    const privateKey = appStorePrivateKey.value();
    const apple: AppStoreCredentials | null =
      issuer && keyId && privateKey ? { issuerId: issuer, keyId, privateKey } : null;
    let bearer: string | undefined;
    if (play) {
      try {
        bearer = await playBearer(play, fetch, now);
      } catch (error) {
        logger.error('refreshStoreEntitlements: play auth', { error: String(error) });
      }
    }
    for (const proof of proofs) {
      try {
        let purchase: VerifiedPurchase | null = null;
        if (proof.store === 'app_store') {
          if (!apple) continue;
          const fetched = await fetchAppleSubscription(proof.token, proof.environment, apple, now, fetch);
          if (fetched.status === 'verified') purchase = fetched.purchase;
          else purchase = { ...revokedProof(proof), revoked: true };
        } else if (play && bearer) {
          const fetched = await fetchPlayPurchase(
            proof.token,
            proof.productId,
            true,
            play,
            now,
            fetch,
            bearer,
          );
          if (fetched.status === 'verified') purchase = fetched.purchase;
          else purchase = { ...revokedProof(proof), revoked: true };
        }
        if (purchase) await grantPurchase(db, proof.uid, purchase, now);
      } catch (error) {
        logger.error('refreshStoreEntitlements', { store: proof.store, error: String(error) });
      }
    }
  },
);

function revokedProof(proof: {
  store: VerifiedPurchase['store'];
  productId: string;
  token: string;
  expiresAt: number | null;
  accountToken: string | null;
  environment: string | null;
  subscription: boolean;
}): VerifiedPurchase {
  return {
    store: proof.store,
    productId: proof.productId,
    token: proof.token,
    expiresAt: proof.expiresAt,
    revoked: true,
    accountToken: proof.accountToken,
    environment: proof.environment,
    subscription: proof.subscription,
  };
}
