import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:abherbs_flutter/camera/plant_id_search.dart';
import 'package:abherbs_flutter/data/prefs.dart';
import 'package:abherbs_flutter/seen/observation.dart';
import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/purchase/store_proof.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum DeleteAccountResult { success, canceled, failed }

Future<DeleteAccountResult> confirmAndDeleteAccount(
    BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(S.of(dialogContext).auth_delete_account),
        content: Text(S.of(dialogContext).auth_delete_account_message),
        actions: <Widget>[
          TextButton(
            child: Text(
              S.of(dialogContext).cancel.toUpperCase(),
              style:
                  const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
          ),
          TextButton(
            child: Text(
              S.of(dialogContext).auth_delete_account_confirm.toUpperCase(),
              style: const TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
          ),
        ],
      );
    },
  );
  if (confirmed != true) {
    return DeleteAccountResult.canceled;
  }
  if (!context.mounted) {
    return DeleteAccountResult.canceled;
  }

  final reauthed = await reauthenticateCurrentUser(context);
  if (reauthed != DeleteAccountResult.success) {
    return reauthed;
  }
  if (!context.mounted) {
    return DeleteAccountResult.canceled;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return const Center(child: CircularProgressIndicator());
    },
  );

  Future<void> hideSpinner() async {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  try {
    await deleteSignedInAccount();
    await hideSpinner();
    return DeleteAccountResult.success;
  } on FirebaseAuthException catch (e) {
    if (e.code != 'requires-recent-login') {
      await hideSpinner();
      return DeleteAccountResult.failed;
    }
    await hideSpinner();
    if (!context.mounted) {
      return DeleteAccountResult.canceled;
    }
    final reauthed = await reauthenticateCurrentUser(context);
    if (reauthed != DeleteAccountResult.success) {
      return reauthed;
    }
    if (!context.mounted) {
      return DeleteAccountResult.canceled;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const Center(child: CircularProgressIndicator());
      },
    );
    try {
      await deleteSignedInAccount();
      await hideSpinner();
      return DeleteAccountResult.success;
    } catch (_) {
      await hideSpinner();
      return DeleteAccountResult.failed;
    }
  } catch (_) {
    await hideSpinner();
    return DeleteAccountResult.failed;
  }
}

void showDeleteAccountResult(BuildContext context, DeleteAccountResult result) {
  if (result == DeleteAccountResult.canceled) {
    return;
  }
  Fluttertoast.showToast(
    msg: result == DeleteAccountResult.success
        ? S.of(context).auth_delete_account_success
        : S.of(context).auth_delete_account_failed,
    toastLength: Toast.LENGTH_LONG,
    gravity: ToastGravity.BOTTOM,
  );
}

Future<void> deleteSignedInAccount() async {
  final user = Auth.firebaseAuth.currentUser;
  if (user == null) {
    throw StateError('not signed in');
  }
  final uid = user.uid;
  await _deleteUserData(uid);
  await user.delete();
  Auth.setUser();
  Purchases.hasOldVersion = false;
  Purchases.clearAccountProducts();
  Auth.credits = 0;
  await Prefs.setBool(keyOldVersion, false);
  await clearPendingStoreProofs();
}

Future<void> _deleteUserData(String uid) async {
  await releaseStorePurchases();
  final privateRoot = privateObservationsReference.child(uid);
  final listEvent = await privateRoot
      .child(firebaseObservationsByDate)
      .child(firebaseAttributeList)
      .once();
  final listValue = listEvent.snapshot.value;
  if (listValue is Map) {
    for (final key in listValue.keys) {
      final raw = listValue[key];
      if (raw is! Map) {
        continue;
      }
      final Observation observation;
      try {
        observation = Observation.fromJson(key, raw);
      } catch (_) {
        continue;
      }
      final id = observation.id.isNotEmpty ? observation.id : key.toString();
      final skip = guideSkipPrivatePhoto;
      if (skip != null) skip(id);
      await publicObservationsReference
          .child(firebaseObservationsByDate)
          .child(firebaseAttributeList)
          .child(id)
          .remove();
      if (observation.plant.isNotEmpty) {
        try {
          await publicObservationsReference
              .child(firebaseObservationsByPlant)
              .child(guideObservationPlantKey(observation.plant))
              .child(firebaseAttributeList)
              .child(id)
              .remove();
        } catch (_) {}
      }
      final privatePaths = <String>[];
      for (final path in observation.photoPaths) {
        if (path is String && path.isNotEmpty) {
          privatePaths.add(path);
          try {
            await firebase_storage.FirebaseStorage.instanceFor(
                    bucket: storageBucket)
                .ref()
                .child(path)
                .delete();
          } catch (_) {}
        }
      }
      final removePrivate = guideDeletePrivatePhotos;
      if (removePrivate != null) await removePrivate(privatePaths);
    }
  }

  await privateRoot.remove();
  await logsObservationsReference.child(uid).remove();
  await logsCreditsReference.child(uid).remove();

  await Future.wait([
    for (final lang in photoSearchLanguageKeys(S.delegate.supportedLocales))
      rootReference
          .child(firebaseUsersPhotoSearch)
          .child(lang)
          .child(uid)
          .remove(),
  ]);

  try {
    await _deleteStorageFolder(
      firebase_storage.FirebaseStorage.instanceFor(bucket: storageBucket)
          .ref()
          .child('observations/$uid'),
    );
  } catch (_) {}

  try {
    await _deleteStorageFolder(
      firebase_storage.FirebaseStorage.instanceFor(bucket: storageBucket)
          .ref()
          .child('private/$uid'),
    );
  } catch (_) {}

  try {
    final docs = await getApplicationDocumentsDirectory();
    final localDir = Directory('${docs.path}/$storageObservations$uid');
    if (await localDir.exists()) {
      await localDir.delete(recursive: true);
    }
  } catch (_) {}

  final userRef = usersReference.child(uid);
  await userRef.child(firebaseAttributeToken).remove();
  await userRef.child(firebaseAttributeFavorite).remove();
  await userRef.child(firebaseAttributePurchases).remove();
  await userRef.child(firebaseAttributeCredits).remove();
  try {
    await userRef.remove();
  } catch (_) {}
}

Future<void> _deleteStorageFolder(firebase_storage.Reference ref) async {
  final result = await ref.listAll();
  for (final item in result.items) {
    await item.delete();
  }
  for (final prefix in result.prefixes) {
    await _deleteStorageFolder(prefix);
  }
}

Future<DeleteAccountResult> reauthenticateCurrentUser(
    BuildContext context) async {
  final user = Auth.firebaseAuth.currentUser;
  if (user == null) {
    return DeleteAccountResult.failed;
  }
  final providers = user.providerData.map((info) => info.providerId).toList();
  try {
    if (providers.contains('google.com')) {
      await GoogleSignIn.instance.initialize();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        return DeleteAccountResult.failed;
      }
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return DeleteAccountResult.success;
    }
    if (providers.contains('apple.com')) {
      final rawNonce = _createNonce(32);
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256ofString(rawNonce),
      );
      final credential = OAuthCredential(
        providerId: 'apple.com',
        signInMethod: 'oauth',
        accessToken: appleCredential.authorizationCode,
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      await user.reauthenticateWithCredential(credential);
      return DeleteAccountResult.success;
    }
    if (providers.contains('password')) {
      final email = user.email;
      if (email == null || !context.mounted) {
        return DeleteAccountResult.failed;
      }
      final password = await _askPassword(context);
      if (password == null || password.isEmpty) {
        return DeleteAccountResult.canceled;
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return DeleteAccountResult.success;
    }
    if (providers.contains('phone')) {
      final phone = user.phoneNumber;
      if (phone == null || !context.mounted) {
        return DeleteAccountResult.failed;
      }
      return await _reauthenticatePhone(context, user, phone)
          ? DeleteAccountResult.success
          : DeleteAccountResult.canceled;
    }
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      return DeleteAccountResult.canceled;
    }
    return DeleteAccountResult.failed;
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) {
      return DeleteAccountResult.canceled;
    }
    return DeleteAccountResult.failed;
  } catch (_) {
    return DeleteAccountResult.failed;
  }
  return DeleteAccountResult.failed;
}

String _sha256ofString(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

String _createNonce(int length) {
  final random = Random.secure();
  final charCodes = List<int>.generate(length, (_) {
    switch (random.nextInt(3)) {
      case 0:
        return random.nextInt(10) + 48;
      case 1:
        return random.nextInt(26) + 65;
      default:
        return random.nextInt(26) + 97;
    }
  });
  return String.fromCharCodes(charCodes);
}

Future<String?> _askPassword(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PasswordReauthDialog(),
  );
}

class _PasswordReauthDialog extends StatefulWidget {
  const _PasswordReauthDialog();

  @override
  State<_PasswordReauthDialog> createState() => _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends State<_PasswordReauthDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).auth_delete_account_reauth),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: S.of(context).auth_password_hint,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).cancel.toUpperCase()),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text(S.of(context).auth_sign_in.toUpperCase()),
          onPressed: () {
            Navigator.of(context).pop(_controller.text);
          },
        ),
      ],
    );
  }
}

Future<bool> _reauthenticatePhone(
    BuildContext context, User user, String phoneNumber) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _PhoneReauthDialog(user: user, phoneNumber: phoneNumber);
    },
  );
  return result == true;
}

class _PhoneReauthDialog extends StatefulWidget {
  final User user;
  final String phoneNumber;

  const _PhoneReauthDialog({required this.user, required this.phoneNumber});

  @override
  State<_PhoneReauthDialog> createState() => _PhoneReauthDialogState();
}

class _PhoneReauthDialogState extends State<_PhoneReauthDialog> {
  final _codeController = TextEditingController();
  String? _verificationId;
  String? _error;
  bool _sending = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    await Auth.firebaseAuth.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          await widget.user.reauthenticateWithCredential(credential);
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _sending = false;
              _error = S.of(context).auth_sign_in_failed;
            });
          }
        }
      },
      verificationFailed: (error) {
        if (mounted) {
          setState(() {
            _sending = false;
            _error = error.message ?? S.of(context).auth_sign_in_failed;
          });
        }
      },
      codeSent: (verificationId, _) {
        if (mounted) {
          setState(() {
            _sending = false;
            _verificationId = verificationId;
          });
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (mounted) {
          setState(() {
            _verificationId = verificationId;
            _sending = false;
          });
        }
      },
    );
  }

  Future<void> _submitCode() async {
    final verificationId = _verificationId;
    final code = _codeController.text.trim();
    if (verificationId == null || code.isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.user.reauthenticateWithCredential(
        PhoneAuthProvider.credential(
            verificationId: verificationId, smsCode: code),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = S.of(context).auth_incorrect_code;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).auth_delete_account_reauth),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_sending) const CircularProgressIndicator(),
          if (!_sending)
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: S.of(context).auth_code_hint,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).cancel.toUpperCase()),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          onPressed: _sending || _submitting ? null : _submitCode,
          child: Text(S.of(context).auth_sign_in.toUpperCase()),
        ),
      ],
    );
  }
}
