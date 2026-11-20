import 'dart:convert';

import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/purchase/account_entitlements.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const _pendingProofs = 'pending_store_proofs';
Future<void> _pendingQueue = Future<void>.value();

Future<void> _enqueuePending(Future<void> Function() task) {
  final next = _pendingQueue.catchError((Object _) {}).then((_) => task());
  _pendingQueue = next;
  return next;
}

Future<void> clearPendingStoreProofs() {
  return _enqueuePending(() => _writePending(const []));
}

enum StoreProofResult { accepted, rejected, deferred }

class StoreProofOutcome {
  final StoreProofResult result;
  final Map<String, bool> products;

  const StoreProofOutcome(this.result, [this.products = const {}]);
}

class _PendingProof {
  final String store;
  final String productId;
  final String proof;

  const _PendingProof(this.store, this.productId, this.proof);

  Map<String, String> toJson() => {
        'store': store,
        'productId': productId,
        'proof': proof,
      };
}

/// Sends the store proof to `submitPurchase`. A signed-out phone keeps the
/// proof and sends it after sign-in. An invalid proof is rejected. A network
/// failure stays deferred and does not unlock the product.
Future<StoreProofOutcome> submitStorePurchase(PurchaseDetails purchase) {
  final store = purchase.verificationData.source;
  if (store != 'app_store' && store != 'google_play') {
    return Future<StoreProofOutcome>.value(
      const StoreProofOutcome(StoreProofResult.deferred),
    );
  }
  return submitStoreProof(
    store: store,
    productId: purchase.productID,
    proof: purchase.verificationData.serverVerificationData,
  );
}

Future<StoreProofOutcome> submitStoreProof({
  required String store,
  required String productId,
  required String proof,
}) async {
  if (productId.isEmpty || proof.isEmpty) {
    return const StoreProofOutcome(StoreProofResult.deferred);
  }
  if (Auth.appUser == null) {
    await _rememberPending(store, productId, proof);
    return const StoreProofOutcome(StoreProofResult.deferred);
  }
  try {
    final response = await FirebaseFunctions.instance
        .httpsCallable(
          'submitPurchase',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call({
      'store': store,
      'productId': productId,
      'proof': proof,
    });
    final products = checkedProductsOf(response.data);
    applyCheckedProducts(products);
    await _dropPending(store, productId);
    return StoreProofOutcome(StoreProofResult.accepted, products);
  } on FirebaseFunctionsException catch (error) {
    if (error.code == 'invalid-argument') {
      await _dropPending(store, productId);
      debugPrint('store proof rejected');
      return const StoreProofOutcome(StoreProofResult.rejected);
    }
    if (error.code == 'already-exists') {
      await _dropPending(store, productId);
      return const StoreProofOutcome(StoreProofResult.deferred);
    }
    await _rememberPending(store, productId, proof);
    debugPrint('store proof: ${error.code}');
    return const StoreProofOutcome(StoreProofResult.deferred);
  } catch (error) {
    await _rememberPending(store, productId, proof);
    debugPrint('store proof: $error');
    return const StoreProofOutcome(StoreProofResult.deferred);
  }
}

Future<void> registerStoreAccount() async {
  if (Auth.appUser == null) return;
  try {
    await FirebaseFunctions.instance
        .httpsCallable(
          'registerStoreAccount',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call();
  } catch (error) {
    debugPrint('store account: $error');
  }
}

Future<void> flushPendingStoreProofs() async {
  if (Auth.appUser == null) return;
  final pending = await _readPending();
  for (final item in pending) {
    await submitStoreProof(
      store: item.store,
      productId: item.productId,
      proof: item.proof,
    );
  }
}

Future<void> releaseStorePurchases() async {
  if (Auth.appUser == null) return;
  try {
    await FirebaseFunctions.instance
        .httpsCallable(
          'releaseStorePurchases',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call();
  } catch (error) {
    debugPrint('release purchases: $error');
    rethrow;
  }
}

Future<List<_PendingProof>> _readPending() async {
  final raw = await Prefs.getStringF(_pendingProofs, '');
  if (raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final pending = <_PendingProof>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final store = item['store'];
      final productId = item['productId'];
      final proof = item['proof'];
      if (store is String && productId is String && proof is String && proof.isNotEmpty) {
        pending.add(_PendingProof(store, productId, proof));
      }
    }
    return pending;
  } catch (_) {
    return [];
  }
}

Future<void> _writePending(List<_PendingProof> pending) async {
  if (pending.isEmpty) {
    await Prefs.setString(_pendingProofs, '');
    return;
  }
  await Prefs.setString(
    _pendingProofs,
    jsonEncode(pending.map((item) => item.toJson()).toList()),
  );
}

Future<void> _rememberPending(String store, String productId, String proof) {
  return _enqueuePending(() async {
    final pending = await _readPending();
    pending.removeWhere(
        (item) => item.store == store && item.productId == productId);
    pending.add(_PendingProof(store, productId, proof));
    final kept =
        pending.length > 8 ? pending.sublist(pending.length - 8) : pending;
    await _writePending(kept);
  });
}

Future<void> _dropPending(String store, String productId) {
  return _enqueuePending(() async {
    final pending = await _readPending();
    final next = pending
        .where((item) => item.store != store || item.productId != productId);
    if (next.length == pending.length) return;
    await _writePending(next.toList());
  });
}
