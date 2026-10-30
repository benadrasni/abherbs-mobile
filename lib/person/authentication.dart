import 'dart:async';

import 'package:abherbs_flutter/purchase/account_entitlements.dart';
import 'package:abherbs_flutter/purchase/owned_purchases.dart';
import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/purchase/store_proof.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:abherbs_flutter/shell/guide_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class Auth {
  static FirebaseAuth firebaseAuth = FirebaseAuth.instance;

  /// The signed-in account. The anonymous guest account is not one.
  static User? appUser = _signedIn(firebaseAuth.currentUser);
  static int credits = 0;
  static int _accountGen = 0;
  static Future<void>? _loadingAccount;
  static StreamSubscription<DatabaseEvent>? _entitlementsSub;

  static User? _signedIn(User? user) =>
      user == null || user.isAnonymous ? null : user;

  /// The anonymous account created at first launch, while no one is signed in.
  static User? get guestUser {
    final user = firebaseAuth.currentUser;
    return user != null && user.isAnonymous ? user : null;
  }

  static void _syncAnalytics() {
    final user = firebaseAuth.currentUser;
    if (user == null) {
      unawaited(GuideAnalytics.syncAccount());
      return;
    }
    final signedIn = !user.isAnonymous;
    final plan = !signedIn
        ? 'free'
        : Purchases.hasFieldGuide()
            ? 'field_guide'
            : Purchases.hasOldVersion
                ? 'legacy'
                : 'free';
    unawaited(GuideAnalytics.syncAccount(
      userId: user.uid,
      account: signedIn ? 'signed_in' : 'guest',
      plan: plan,
      ads: signedIn && !Purchases.showsAds() ? 'hidden' : 'shown',
      legacyPaid: signedIn && Purchases.hasOldVersion,
    ));
  }

  static void _logAuth(UserCredential result, String providerId, bool signUp) {
    final method = guideAnalyticsAuthMethod(providerId);
    final uid = result.user?.uid;
    if (signUp) {
      unawaited(GuideAnalytics.signUp(method, userId: uid));
    } else {
      unawaited(GuideAnalytics.login(method, userId: uid));
    }
  }

  /// Creates the guest account once per install. Signing out does not create
  /// another, so its one free identification is not handed out again.
  static Future<void> startGuest() async {
    if (firebaseAuth.currentUser != null) return;
    if (Prefs.getBool(keyGuestCreated, false)) return;
    try {
      await firebaseAuth.signInAnonymously();
      await Prefs.setBool(keyGuestCreated, true);
      _syncAnalytics();
    } catch (error) {
      debugPrint('guest account: $error');
    }
  }

  /// Links the guest account so its uid, and the identification it used,
  /// carry over. A credential that already has an account signs in to it.
  static Future<UserCredential> _linkOrSignIn(AuthCredential credential) async {
    final guest = guestUser;
    if (guest != null) {
      try {
        final linked = await guest.linkWithCredential(credential);
        _logAuth(linked, credential.providerId, true);
        return linked;
      } on FirebaseAuthException catch (error) {
        if (error.code != 'credential-already-in-use' &&
            error.code != 'email-already-in-use') {
          rethrow;
        }
        final signed = await firebaseAuth
            .signInWithCredential(error.credential ?? credential);
        _logAuth(signed, credential.providerId, false);
        return signed;
      }
    }
    final signed = await firebaseAuth.signInWithCredential(credential);
    _logAuth(signed, credential.providerId, false);
    return signed;
  }

  static Future<void> signInWithCredential(AuthCredential credential) async {
    await _linkOrSignIn(credential);
    setUser();
  }

  static Future<User?> signInWithEmail(String email, String password) async {
    UserCredential result = await firebaseAuth.signInWithEmailAndPassword(
        email: email, password: password);
    _logAuth(result, 'password', false);
    setUser();
    return result.user;
  }

  static Future<User?> signUpWithEmail(String email, String password) async {
    final guest = guestUser;
    UserCredential result = guest != null
        ? await guest.linkWithCredential(
            EmailAuthProvider.credential(email: email, password: password))
        : await firebaseAuth.createUserWithEmailAndPassword(
            email: email, password: password);
    _logAuth(result, 'password', true);
    setUser();
    return result.user;
  }

  static Future<void> resetPassword(String email) async {
    return firebaseAuth.sendPasswordResetEmail(email: email);
  }

  static Future<void> signUpWithPhone(
      PhoneVerificationCompleted verificationCompleted,
      PhoneVerificationFailed verificationFailed,
      PhoneCodeSent codeSent,
      PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
      String phoneNumber,
      [int? token]) async {
    await firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 5),
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      forceResendingToken: token,
    );
  }

  /// How long the account row may take before the copy already on the phone
  /// is used. These reads do not finish or throw while the phone is offline.
  static const _accountReadWait = Duration(seconds: 4);

  /// A previous read already applied this account. A later read that does not
  /// finish must not drop that plan or the name count.
  static bool _accountHeld() {
    return Purchases.namesReady ||
        Purchases.accountProducts.isNotEmpty ||
        Purchases.hasOldVersion ||
        credits != 0;
  }

  /// Reads the signed-in account. Callers share one read until it finishes,
  /// so Find can wait for credits and purchased features before it redraws.
  static Future<void> setUser() {
    final pending = _loadingAccount;
    if (pending != null) return pending;
    late final Future<void> run;
    run = _readAccount().whenComplete(() {
      if (identical(_loadingAccount, run)) _loadingAccount = null;
    });
    _loadingAccount = run;
    return run;
  }

  static Future<void> _readAccount() async {
    final gen = _accountGen;
    final user = _signedIn(firebaseAuth.currentUser);
    if (gen != _accountGen) return;
    appUser = user;
    if (user == null) {
      _stopEntitlements();
      credits = 0;
      Purchases.hasOldVersion = false;
      Purchases.clearAccountProducts();
      if (gen == _accountGen) {
        Purchases.finishNames();
        _syncAnalytics();
      }
      return;
    }
    final uid = user.uid;
    unawaited(guideKeepSynced(usersReference.child(uid), true));
    final held = _accountHeld();
    var entitlementsRead = false;
    try {
      final event =
          await usersReference.child(uid).once().timeout(_accountReadWait);
      if (gen != _accountGen) return;
      var value = event.snapshot.value;
      try {
        // once() can return the on-disk user from before this phone's plan
        // was written. A child that comes back replaces that copy. A null
        // child is not the server removing the plan, so the stored row stays.
        final fresh = await guideServerGet(
          usersReference.child(uid).child('entitlements'),
        ).timeout(_accountReadWait);
        if (gen != _accountGen) return;
        if (fresh.value != null) {
          entitlementsRead = true;
          value = userWithFreshEntitlements(value, fresh.value);
        }
      } catch (error) {
        debugPrint('entitlements: $error');
      }
      if (value is Map) {
        final old = value[firebaseAttributeOldVersion];
        Purchases.hasOldVersion = old == true;
        final rawCredits = value[firebaseAttributeCredits];
        credits = rawCredits is int ? rawCredits : 0;
        final entitlements = accountEntitlementsOf(value);
        if (shouldApplyAccountEntitlements(
          entitlementsRead: entitlementsRead,
          planHeld: held,
        )) {
          applyAccountEntitlements(entitlements);
          final revoked = revokedEntitlementIds(entitlements).toSet();
          unawaited(() async {
            await forgetRevokedPurchases(revoked);
            if (gen != _accountGen || appUser?.uid != uid) return;
            final purchases = await Prefs.getStringListF(keyPurchases, []);
            if (purchases.isEmpty) return;
            await rememberStorePurchases(purchases);
          }());
        }
      } else {
        Purchases.hasOldVersion = false;
        credits = 0;
        Purchases.clearAccountProducts();
        unawaited(Prefs.getStringListF(keyPurchases, []).then((purchases) {
          if (gen != _accountGen || purchases.isEmpty || appUser?.uid != uid) {
            return Future<void>.value();
          }
          return rememberStorePurchases(purchases);
        }));
      }
      unawaited(Prefs.setBool(keyOldVersion, Purchases.hasOldVersion));
      unawaited(Prefs.getStringF(keyToken).then((token) {
        if (gen != _accountGen || token.isEmpty || appUser?.uid != uid) return;
        usersReference.child(uid).child(firebaseAttributeToken).set(token);
      }));
    } catch (error) {
      if (gen != _accountGen) return;
      debugPrint('account: $error');
      if (!held) {
        credits = 0;
        Purchases.failedAccountRead();
      }
      if (gen == _accountGen) _syncAnalytics();
    }

    if (Purchases.isPhotoSearch()) {
      unawaited(guideKeepSynced(
        rootReference.child(firebaseSearchPhoto).child(firebaseAttributeEntity),
        true,
      ));
    }

    if (gen == _accountGen) {
      Purchases.finishNames();
      _syncAnalytics();
      _watchEntitlements(uid, gen);
      unawaited(registerStoreAccount());
      unawaited(flushPendingStoreProofs());
    }
  }

  /// Later checks, expiries, and the other phone's purchase. The account
  /// read above already applied the current row, so this does not upload
  /// the local store list again.
  static void _watchEntitlements(String uid, int gen) {
    _stopEntitlements();
    final watch = EntitlementWatch();
    _entitlementsSub =
        usersReference.child(uid).child('entitlements').onValue.listen((event) {
      if (gen != _accountGen || appUser?.uid != uid) return;
      final raw = event.snapshot.value;
      final snapshot = accountEntitlementsOf(
        raw == null
            ? <String, Object?>{}
            : <String, Object?>{'entitlements': raw},
      );
      if (!watch.shouldApply(snapshot)) return;
      applyAccountEntitlements(snapshot);
      _syncAnalytics();
      unawaited(forgetRevokedPurchases(revokedEntitlementIds(snapshot)));
    }, onError: (Object error) {
      debugPrint('entitlements: $error');
    });
  }

  static void _stopEntitlements() {
    final sub = _entitlementsSub;
    _entitlementsSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  static Future<void> signOut() async {
    _accountGen++;
    _loadingAccount = null;
    _stopEntitlements();
    appUser = null;
    credits = 0;
    Purchases.clearAccountProducts();
    await firebaseAuth.signOut();
    _syncAnalytics();
  }

  /// Linking the guest account keeps the same user, so `authStateChanges`
  /// stays quiet; `userChanges` reports it. Listeners see the guest as null.
  static StreamSubscription<User?> subscribe(void Function(User?) listener) {
    return firebaseAuth.userChanges().listen((user) {
      final signedIn = _signedIn(user);
      appUser = signedIn;
      if (Purchases.holdNamesFor(signedIn?.uid)) credits = 0;
      listener(signedIn);
    });
  }
}
