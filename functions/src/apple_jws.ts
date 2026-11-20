import { verify, X509Certificate } from 'node:crypto';
import { decodeBase64Url } from './jwt';

/// Apple Root CA - G3. Public certificate, fingerprint pinned below.
export const appleRootCaG3Pem = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

export const appleRootFingerprint256 =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

export const appStoreBundleId = 'sk.ab.herbs';

function certificateCurrent(certificate: X509Certificate, now: number): boolean {
  const from = Date.parse(certificate.validFrom);
  const to = Date.parse(certificate.validTo);
  if (!Number.isFinite(from) || !Number.isFinite(to)) return false;
  return from <= now && to >= now;
}

/// App Store receipt signing: leaf, then the WWDR intermediate.
const appleReceiptLeafOid = '1.2.840.113635.100.6.11.1';
const appleReceiptIntermediateOid = '1.2.840.113635.100.6.2.1';

type DerSpan = { tag: number; start: number; end: number };

function derSpan(raw: Buffer, offset: number): DerSpan | null {
  if (offset < 0 || offset + 1 >= raw.length) return null;
  const tag = raw[offset];
  const lengthByte = raw[offset + 1];
  let length = lengthByte;
  let start = offset + 2;
  if (lengthByte & 0x80) {
    const count = lengthByte & 0x7f;
    if (count === 0 || count > 4 || offset + 2 + count > raw.length) return null;
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + raw[offset + 2 + i];
    start = offset + 2 + count;
  }
  const end = start + length;
  if (end > raw.length) return null;
  return { tag, start, end };
}

function oidText(raw: Buffer, start: number, end: number): string | null {
  if (end <= start) return null;
  const parts = [Math.floor(raw[start] / 40), raw[start] % 40];
  let value = 0;
  let pending = false;
  for (let i = start + 1; i < end; i++) {
    value = value * 128 + (raw[i] & 0x7f);
    pending = true;
    if ((raw[i] & 0x80) === 0) {
      parts.push(value);
      value = 0;
      pending = false;
    }
  }
  if (pending) return null;
  return parts.join('.');
}

/// X509Certificate does not list extension OIDs, so read them from the DER.
function extensionOids(certificate: X509Certificate): Set<string> | null {
  const raw = certificate.raw;
  const certificateSpan = derSpan(raw, 0);
  if (!certificateSpan || certificateSpan.tag !== 0x30) return null;
  const body = derSpan(raw, certificateSpan.start);
  if (!body || body.tag !== 0x30) return null;
  const oids = new Set<string>();
  let offset = body.start;
  while (offset < body.end) {
    const field = derSpan(raw, offset);
    if (!field || field.end <= offset) return null;
    if (field.tag === 0xa3) {
      const extensions = derSpan(raw, field.start);
      if (!extensions || extensions.tag !== 0x30) return null;
      let extAt = extensions.start;
      while (extAt < extensions.end) {
        const extension = derSpan(raw, extAt);
        if (!extension || extension.tag !== 0x30 || extension.end <= extAt) return null;
        const oid = derSpan(raw, extension.start);
        if (!oid || oid.tag !== 0x06) return null;
        const text = oidText(raw, oid.start, oid.end);
        if (!text) return null;
        oids.add(text);
        extAt = extension.end;
      }
    }
    offset = field.end;
  }
  return oids;
}

function storeKitCertificates(certificates: X509Certificate[]): boolean {
  const leaf = certificates[0];
  const intermediate = certificates[1];
  if (leaf.ca || !intermediate.ca) return false;
  const leafOids = extensionOids(leaf);
  const intermediateOids = extensionOids(intermediate);
  if (!leafOids || !intermediateOids) return false;
  return leafOids.has(appleReceiptLeafOid) && intermediateOids.has(appleReceiptIntermediateOid);
}

/**
 * Verifies a StoreKit 2 JWS against [rootPem] and returns the payload.
 * The leaf must carry Apple's receipt OID and must not be a CA. The next
 * certificate must be a CA with the intermediate OID. The chain up to that
 * root, and the leaf signature, must hold.
 */
export function verifyAppleSignedPayload(
  jws: string,
  now: number,
  rootPem = appleRootCaG3Pem,
): Record<string, unknown> | null {
  const parts = jws.split('.');
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) return null;
  let header: { alg?: unknown; x5c?: unknown };
  let payload: unknown;
  try {
    header = JSON.parse(decodeBase64Url(parts[0]).toString('utf8')) as { alg?: unknown; x5c?: unknown };
    payload = JSON.parse(decodeBase64Url(parts[1]).toString('utf8'));
  } catch {
    return null;
  }
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length < 2) return null;
  if (header.x5c.some((entry) => typeof entry !== 'string' || entry.length === 0)) return null;

  let root: X509Certificate;
  let certificates: X509Certificate[];
  try {
    root = new X509Certificate(rootPem);
    certificates = header.x5c.map((entry) => new X509Certificate(Buffer.from(entry, 'base64')));
  } catch {
    return null;
  }
  if (rootPem === appleRootCaG3Pem && root.fingerprint256 !== appleRootFingerprint256) return null;
  if (certificates.some((certificate) => !certificateCurrent(certificate, now))) return null;

  for (let i = 0; i < certificates.length - 1; i++) {
    if (!certificates[i].verify(certificates[i + 1].publicKey)) return null;
  }
  const top = certificates[certificates.length - 1];
  const topIsRoot = top.fingerprint256 === root.fingerprint256;
  if (!topIsRoot && !top.verify(root.publicKey)) return null;
  if (!storeKitCertificates(certificates)) return null;

  const signatureOk = verify(
    'sha256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    { key: certificates[0].publicKey, dsaEncoding: 'ieee-p1363' },
    decodeBase64Url(parts[2]),
  );
  if (!signatureOk || !payload || typeof payload !== 'object') return null;
  return payload as Record<string, unknown>;
}

export type AppleTransaction = {
  productId: string;
  transactionId: string | null;
  originalTransactionId: string;
  expiresAt: number | null;
  revoked: boolean;
  signedDate: number | null;
  appAccountToken: string | null;
  environment: string | null;
};

export function appleTransaction(payload: Record<string, unknown>): AppleTransaction | null {
  if (payload.bundleId !== appStoreBundleId) return null;
  const productId = payload.productId;
  const originalTransactionId = payload.originalTransactionId;
  if (typeof productId !== 'string' || !/^[A-Za-z0-9_]{1,64}$/.test(productId)) return null;
  if (typeof originalTransactionId !== 'string' || !/^[0-9]{1,32}$/.test(originalTransactionId)) {
    return null;
  }
  const transactionId =
    typeof payload.transactionId === 'string' && /^[0-9]{1,32}$/.test(payload.transactionId)
      ? payload.transactionId
      : null;
  const expiresAt = typeof payload.expiresDate === 'number' ? payload.expiresDate : null;
  const revoked = typeof payload.revocationDate === 'number';
  const signedDate =
    typeof payload.signedDate === 'number' && Number.isFinite(payload.signedDate)
      ? payload.signedDate
      : null;
  const appAccountToken = typeof payload.appAccountToken === 'string' ? payload.appAccountToken : null;
  const environment = typeof payload.environment === 'string' ? payload.environment : null;
  return {
    productId,
    transactionId,
    originalTransactionId,
    expiresAt,
    revoked,
    signedDate,
    appAccountToken,
    environment,
  };
}

export function signedTransactionsFromStatus(body: unknown): string[] {
  if (!body || typeof body !== 'object') return [];
  const data = (body as { data?: unknown }).data;
  if (!Array.isArray(data)) return [];
  const signed: string[] = [];
  for (const group of data) {
    if (!group || typeof group !== 'object') continue;
    const last = (group as { lastTransactions?: unknown }).lastTransactions;
    if (!Array.isArray(last)) continue;
    for (const row of last) {
      if (!row || typeof row !== 'object') continue;
      const info = (row as { signedTransactionInfo?: unknown }).signedTransactionInfo;
      if (typeof info === 'string' && info.length > 0) signed.push(info);
    }
  }
  return signed;
}
