import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/person/guide_sign_in.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/offline/offline.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_picker/country_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum _Step { providers, email, phone, code }

enum _Busy { apple, google, email, reset, phone, code }

/// The field-guide sign-in page. Apple and Google are full-width buttons.
/// Email and phone open on this same page. Closing it returns to the opener.
class GuideSignInPage extends StatefulWidget {
  final bool? showApple;
  final GuideAppearance? appearance;
  final Country? initialCountry;
  final WidgetBuilder? plate;
  final Future<void> Function()? onApple;
  final Future<void> Function()? onGoogle;
  final Future<GuideEmailFollowUp> Function(String email, String password)?
      onEmail;
  final Future<void> Function(String email)? onResetPassword;
  final Future<void> Function(String phone)? onSendCode;
  final Future<void> Function(String code)? onConfirmCode;
  final void Function(String url)? onOpenUrl;

  const GuideSignInPage({
    super.key,
    this.showApple,
    this.appearance,
    this.initialCountry,
    this.plate,
    this.onApple,
    this.onGoogle,
    this.onEmail,
    this.onResetPassword,
    this.onSendCode,
    this.onConfirmCode,
    this.onOpenUrl,
  });

  @override
  State<GuideSignInPage> createState() => _GuideSignInPageState();
}

class _GuideSignInPageState extends State<GuideSignInPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();

  _Step _step = _Step.providers;
  _Busy? _busy;
  String? _error;
  String? _sentTo;
  String? _verificationId;
  int? _resendToken;
  Country? _country;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _showApple => widget.showApple ?? Platform.isIOS;

  void _leave() {
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _retreat() {
    setState(() {
      _error = null;
      _busy = null;
      _step = _step == _Step.code ? _Step.phone : _Step.providers;
    });
  }

  void _show(_Step step) {
    setState(() {
      _error = null;
      _step = step;
    });
  }

  Future<void> _run(_Busy busy, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = busy;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      debugPrint('guide sign-in: $error');
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _messageFor(Object error) {
    final strings = S.of(context);
    if (error is FirebaseAuthException) {
      switch (guidePhoneFailure(error.code)) {
        case GuidePhoneFailure.invalidNumber:
          return strings.auth_invalid_phone_number;
        case GuidePhoneFailure.wrongCode:
          return strings.auth_incorrect_code;
        case GuidePhoneFailure.failed:
          return strings.auth_sign_in_failed;
      }
    }
    return strings.auth_sign_in_failed;
  }

  Future<void> _apple() {
    return _run(_Busy.apple, () async {
      final custom = widget.onApple;
      if (custom != null) {
        await custom();
        _leave();
        return;
      }
      try {
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
        await Auth.signInWithCredential(credential);
        _leave();
      } on SignInWithAppleAuthorizationException catch (error) {
        if (error.code == AuthorizationErrorCode.canceled) return;
        rethrow;
      }
    });
  }

  Future<void> _google() {
    return _run(_Busy.google, () async {
      final custom = widget.onGoogle;
      if (custom != null) {
        await custom();
        _leave();
        return;
      }
      try {
        try {
          await GoogleSignIn.instance.initialize();
        } catch (error) {
          debugPrint('guide sign-in: $error');
        }
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null) return;
        await Auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
        _leave();
      } on GoogleSignInException catch (error) {
        if (error.code == GoogleSignInExceptionCode.canceled) return;
        rethrow;
      }
    });
  }

  Future<void> _submitEmail() async {
    final strings = S.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    if (!guideEmailLooksValid(email)) {
      setState(() => _error = strings.auth_invalid_email_address);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = strings.auth_empty_password);
      return;
    }
    if (password.length < 6) {
      setState(() => _error = strings.guide_sign_in_short_password);
      return;
    }
    GuideEmailFollowUp? follow;
    await _run(_Busy.email, () async {
      follow = widget.onEmail == null
          ? await guideSignInEmail(email, password)
          : await widget.onEmail!(email, password);
    });
    if (!mounted || follow == null) return;
    switch (follow!) {
      case GuideEmailFollowUp.signedIn:
        _leave();
      case GuideEmailFollowUp.needsVerification:
        try {
          await _showVerify();
        } finally {
          if (widget.onEmail == null) await Auth.signOut();
        }
      case GuideEmailFollowUp.wrongPassword:
        setState(() => _error = strings.guide_sign_in_wrong_password);
      case GuideEmailFollowUp.shortPassword:
        setState(() => _error = strings.guide_sign_in_short_password);
      case GuideEmailFollowUp.tryCreate:
      case GuideEmailFollowUp.failed:
        setState(() => _error = strings.auth_sign_in_failed);
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!guideEmailLooksValid(email)) {
      setState(() => _error = S.of(context).auth_invalid_email_address);
      return;
    }
    var sent = false;
    await _run(_Busy.reset, () async {
      final custom = widget.onResetPassword;
      if (custom != null) {
        await custom(email);
      } else {
        await Auth.resetPassword(email);
      }
      sent = true;
    });
    if (sent && mounted) await _showReset(email);
  }

  Future<void> _submitPhone() async {
    final phone = guidePhoneNumber(
      _selectedCountry(context).phoneCode,
      _phone.text,
    );
    if (phone.isEmpty) {
      setState(() => _error = S.of(context).auth_invalid_phone_number);
      return;
    }
    await _run(_Busy.phone, () async {
      if (!await _send(phone)) return;
      if (!mounted) return;
      setState(() {
        _sentTo = phone;
        _code.clear();
        _step = _Step.code;
      });
    });
  }

  Future<void> _resend() async {
    final phone = _sentTo;
    if (phone == null || phone.isEmpty) return;
    await _run(_Busy.phone, () async {
      await _send(phone, resend: true);
    });
  }

  /// Sends the code. Returns false when the phone itself signed in.
  Future<bool> _send(String phone, {bool resend = false}) async {
    final custom = widget.onSendCode;
    if (custom != null) {
      await custom(phone);
      return true;
    }
    final signedIn = await _verifyPhone(phone, resend: resend);
    if (signedIn) {
      _leave();
      return false;
    }
    return true;
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = S.of(context).auth_invalid_code);
      return;
    }
    await _run(_Busy.code, () async {
      final custom = widget.onConfirmCode;
      if (custom != null) {
        await custom(code);
      } else {
        final verificationId = _verificationId;
        if (verificationId == null) {
          throw FirebaseAuthException(code: 'session-expired');
        }
        await Auth.signInWithCredential(
          PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: code,
          ),
        );
      }
      _leave();
    });
  }

  Future<bool> _verifyPhone(String phone, {bool resend = false}) async {
    final done = Completer<void>();
    var signedIn = false;
    await Auth.signUpWithPhone(
      (credential) async {
        try {
          await Auth.signInWithCredential(credential);
          signedIn = true;
          if (!done.isCompleted) {
            done.complete();
          } else if (mounted) {
            _leave();
          }
        } catch (error) {
          if (!done.isCompleted) done.completeError(error);
        }
      },
      (error) {
        if (!done.isCompleted) done.completeError(error);
      },
      (verificationId, token) {
        _verificationId = verificationId;
        _resendToken = token;
        if (!done.isCompleted) done.complete();
      },
      (verificationId) {
        _verificationId = verificationId;
        if (!done.isCompleted) done.complete();
      },
      phone,
      resend ? _resendToken : null,
    );
    await done.future.timeout(const Duration(seconds: 60));
    return signedIn;
  }

  Future<void> _showVerify() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final strings = S.of(dialogContext);
        return AlertDialog(
          title: Text(strings.auth_verify_email_title),
          content: Text(strings.auth_verify_email_message),
          actions: [
            TextButton(
              onPressed: () {
                if (widget.onEmail == null) {
                  Auth.firebaseAuth.currentUser?.sendEmailVerification();
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(strings.auth_resend_email),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showReset(String email) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final strings = S.of(dialogContext);
        return AlertDialog(
          title: Text(strings.auth_reset_password_email_title),
          content: Text(strings.auth_reset_password_email_message(email)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.close),
            ),
          ],
        );
      },
    );
  }

  void _openUrl(String url) {
    final custom = widget.onOpenUrl;
    if (custom != null) {
      custom(url);
      return;
    }
    launchURL(url);
  }

  Country _selectedCountry(BuildContext context) {
    final chosen = _country ?? widget.initialCountry;
    if (chosen != null) return chosen;
    final code = Localizations.localeOf(context).countryCode;
    if (code != null && code.isNotEmpty) {
      try {
        return Country.parse(code);
      } catch (_) {}
    }
    return Country.parse('US');
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GuideTheme(
        appearance: widget.appearance,
        child: const _CallingCodeSheet(),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _country = selected);
  }

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      appearance: widget.appearance,
      navigationColor: (colors) => colors.paper,
      child: Builder(
        builder: (context) {
          final colors = GuideColors.of(context);
          return PopScope(
            canPop: _step == _Step.providers,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _retreat();
            },
            child: Scaffold(
              backgroundColor: colors.paper,
              body: SafeArea(
                bottom: false,
                child: GuideReadable(
                  maxWidth: 880,
                  child: _step == _Step.providers
                      ? _providers(context)
                      : _form(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _providers(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final dark = colors.isDark;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        SizedBox(
          height: 206,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 236,
                child: IgnorePointer(
                  child: _HeroPlate(plate: widget.plate),
                ),
              ),
              PositionedDirectional(
                top: 10,
                end: 12,
                child: _CloseButton(
                  label: strings.guide_sign_in_not_now,
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            strings.auth_sign_in,
            style: TextStyle(
              fontFamily: GuideType.serif,
              fontWeight: FontWeight.w500,
              fontSize: 34,
              letterSpacing: -0.68,
              height: 1.05,
              color: colors.ink,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            strings.guide_sign_in_free,
            style: TextStyle(color: colors.ink2, fontSize: 16, height: 1.45),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Column(
            children: [
              _Perk(
                title: strings.guide_sign_in_names,
                note: strings.guide_sign_in_names_note,
              ),
              _Perk(
                title: strings.guide_sign_in_seen,
                note: strings.guide_sign_in_seen_note,
              ),
              _Perk(
                title: strings.guide_sign_in_share,
                note: strings.guide_sign_in_share_note,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showApple) ...[
                _ProviderButton(
                  label: strings.guide_sign_in_apple,
                  icon: _AppleMark(
                    dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                  ),
                  background:
                      dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
                  foreground:
                      dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                  spinning: _busy == _Busy.apple,
                  onPressed: _busy == null ? () => unawaited(_apple()) : null,
                ),
                const SizedBox(height: 10),
              ],
              _ProviderButton(
                label: strings.guide_sign_in_google,
                icon: Image.asset(
                  'res/images/go-logo.png',
                  width: 20,
                  height: 20,
                ),
                background:
                    dark ? const Color(0xFF131314) : const Color(0xFFFFFFFF),
                foreground:
                    dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F),
                border:
                    dark ? const Color(0xFF8E918F) : const Color(0xFF747775),
                spinning: _busy == _Busy.google,
                onPressed: _busy == null ? () => unawaited(_google()) : null,
              ),
              const _OrRule(),
              Row(
                children: [
                  Expanded(
                    child: _ProviderButton(
                      label: strings.guide_sign_in_email,
                      icon: Icon(Icons.mail_outline,
                          size: 20, color: colors.ink2),
                      background: colors.cream,
                      foreground: colors.ink,
                      border: colors.rule,
                      fontSize: 15,
                      iconStart: 16,
                      onPressed:
                          _busy == null ? () => _show(_Step.email) : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProviderButton(
                      label: strings.guide_sign_in_phone,
                      icon: Icon(
                        Icons.smartphone_outlined,
                        size: 20,
                        color: colors.ink2,
                      ),
                      background: colors.cream,
                      foreground: colors.ink,
                      border: colors.rule,
                      fontSize: 15,
                      iconStart: 16,
                      onPressed:
                          _busy == null ? () => _show(_Step.phone) : null,
                    ),
                  ),
                ],
              ),
              if (_error != null) _ErrorText(_error!),
              _Legal(onOpen: _openUrl),
            ],
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    final codeStep = _step == _Step.code;
    return ListView(
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        GuideBackButton(
          label: codeStep ? strings.guide_back : strings.auth_sign_in,
          onPressed: _retreat,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_formTitle(strings), style: GuideType.question(colors)),
              const SizedBox(height: 4),
              Text(
                _formNote(strings),
                style:
                    TextStyle(color: colors.ink2, fontSize: 16, height: 1.45),
              ),
              const SizedBox(height: 16),
              ..._formFields(context, strings, colors),
              const SizedBox(height: 6),
              _PrimaryButton(
                label: _primaryLabel(strings),
                spinning: _busy == _Busy.email ||
                    (_step == _Step.phone && _busy == _Busy.phone) ||
                    _busy == _Busy.code,
                onPressed: _busy == null ? _primary() : null,
              ),
              if (_step == _Step.email)
                _MossButton(
                  label: strings.guide_sign_in_forgot,
                  onPressed: _busy == null ? () => unawaited(_reset()) : null,
                ),
              if (codeStep)
                _MossButton(
                  label: strings.guide_sign_in_resend,
                  onPressed: _busy == null ? () => unawaited(_resend()) : null,
                ),
              if (_error != null) _ErrorText(_error!),
              _Legal(onOpen: _openUrl),
            ],
          ),
        ),
      ],
    );
  }

  String _formTitle(S strings) {
    switch (_step) {
      case _Step.email:
        return strings.auth_email;
      case _Step.phone:
        return strings.auth_phone;
      case _Step.code:
        return strings.guide_sign_in_code;
      case _Step.providers:
        return strings.auth_sign_in;
    }
  }

  String _formNote(S strings) {
    switch (_step) {
      case _Step.email:
        return strings.guide_sign_in_email_new;
      case _Step.phone:
        return strings.guide_sign_in_phone_note;
      case _Step.code:
        return strings.guide_sign_in_code_note(_sentTo ?? '');
      case _Step.providers:
        return strings.guide_sign_in_free;
    }
  }

  String _primaryLabel(S strings) {
    switch (_step) {
      case _Step.phone:
        return strings.guide_sign_in_send_code;
      case _Step.email:
      case _Step.code:
      case _Step.providers:
        return strings.guide_sign_in_continue;
    }
  }

  VoidCallback _primary() {
    switch (_step) {
      case _Step.email:
        return () => unawaited(_submitEmail());
      case _Step.phone:
        return () => unawaited(_submitPhone());
      case _Step.code:
        return () => unawaited(_submitCode());
      case _Step.providers:
        return () {};
    }
  }

  List<Widget> _formFields(
      BuildContext context, S strings, GuideColors colors) {
    switch (_step) {
      case _Step.email:
        return [
          _Field(
            fieldKey: const Key('guideSignInEmail'),
            controller: _email,
            hint: strings.auth_email_hint,
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
          ),
          _Field(
            fieldKey: const Key('guideSignInPassword'),
            controller: _password,
            hint: strings.auth_password_hint,
            obscure: true,
            autofill: const [AutofillHints.password],
          ),
        ];
      case _Step.phone:
        final country = _selectedCountry(context);
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                _CallingCode(
                  code: '+${country.phoneCode}',
                  onPressed: _pickCountry,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    fieldKey: const Key('guideSignInPhone'),
                    controller: _phone,
                    hint: strings.auth_phone_hint,
                    keyboard: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                    autofill: const [AutofillHints.telephoneNumber],
                    gap: false,
                  ),
                ),
              ],
            ),
          ),
        ];
      case _Step.code:
        return [
          _Field(
            fieldKey: const Key('guideSignInCode'),
            controller: _code,
            hint: strings.auth_code_hint,
            keyboard: TextInputType.number,
            autofill: const [AutofillHints.oneTimeCode],
            maxLength: 6,
          ),
        ];
      case _Step.providers:
        return const [];
    }
  }
}

/// Signs in, or creates the account when Firebase has no user for this email.
Future<GuideEmailFollowUp> guideSignInEmail(
  String email,
  String password,
) async {
  User? existing;
  try {
    existing = await Auth.signInWithEmail(email, password);
  } on FirebaseAuthException catch (error) {
    final next = guideEmailFollowUp(creating: false, code: error.code);
    if (next != GuideEmailFollowUp.tryCreate) return next;
  } catch (error) {
    debugPrint('guide sign-in: $error');
    return GuideEmailFollowUp.failed;
  }
  if (existing != null) {
    if (existing.emailVerified) return GuideEmailFollowUp.signedIn;
    try {
      await existing.sendEmailVerification();
    } catch (error) {
      debugPrint('guide sign-in: $error');
    }
    return GuideEmailFollowUp.needsVerification;
  }
  try {
    final user = await Auth.signUpWithEmail(email, password);
    if (user == null) return GuideEmailFollowUp.failed;
    await user.sendEmailVerification();
    return GuideEmailFollowUp.needsVerification;
  } on FirebaseAuthException catch (error) {
    final next = guideEmailFollowUp(creating: true, code: error.code);
    if (next == GuideEmailFollowUp.tryCreate) return GuideEmailFollowUp.failed;
    return next;
  } catch (error) {
    debugPrint('guide sign-in: $error');
    return GuideEmailFollowUp.failed;
  }
}

Future<void> openGuideSignIn(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: guideSignInRouteName),
      builder: (context) => const GuideSignInPage(),
    ),
  );
}

String _sha256ofString(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

String _createNonce(int length) {
  final random = Random.secure();
  final codes = List<int>.generate(length, (_) {
    switch (random.nextInt(3)) {
      case 0:
        return random.nextInt(10) + 48;
      case 1:
        return random.nextInt(26) + 65;
      default:
        return random.nextInt(26) + 97;
    }
  });
  return String.fromCharCodes(codes);
}

class _HeroPlate extends StatelessWidget {
  const _HeroPlate({this.plate});

  final WidgetBuilder? plate;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.plateWell),
          plate?.call(context) ?? const _DefaultPlate(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.paper.withValues(alpha: 0),
                  colors.paper.withValues(alpha: 0),
                  colors.paper,
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultPlate extends StatelessWidget {
  const _DefaultPlate();

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: GuideColors.of(context).plateWell);
    return FutureBuilder<File?>(
      future: Offline.getLocalFile(guideSignInPlatePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          return placeholder;
        }
        final file = snapshot.data;
        if (file != null) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            errorBuilder: (context, error, stackTrace) => placeholder,
          );
        }
        return CachedNetworkImage(
          imageUrl: storageEndpoint + guideSignInPlatePath,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.2),
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
        );
      },
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: colors.cream,
          shape: CircleBorder(side: BorderSide(color: colors.rule)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.close, size: 20, color: colors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(
              child: Icon(Icons.check, size: 18, color: colors.moss),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                Text(
                  note,
                  style: TextStyle(
                    color: colors.ink2,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.border,
    this.fontSize = 16,
    this.iconStart = 20,
    this.spinning = false,
  });

  final String label;
  final Widget icon;
  final Color background;
  final Color foreground;
  final Color? border;
  final double fontSize;
  final double iconStart;
  final VoidCallback? onPressed;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: StadiumBorder(
        side: border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: spinning ? null : onPressed,
        child: SizedBox(
          height: 50,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 44),
                child: spinning
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
              ),
              if (!spinning)
                PositionedDirectional(start: iconStart, child: icon),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrRule extends StatelessWidget {
  const _OrRule();

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Expanded(child: _line(colors)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              S.of(context).guide_sign_in_or,
              style: TextStyle(fontSize: 13, color: colors.ink3),
            ),
          ),
          Expanded(child: _line(colors)),
        ],
      ),
    );
  }

  Widget _line(GuideColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.rule),
      child: const SizedBox(height: 1),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.spinning = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GuideColors.of(context).mossFill,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: spinning ? null : onPressed,
        child: SizedBox(
          height: 44,
          child: Center(
            child: spinning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MossButton extends StatelessWidget {
  const _MossButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: GuideColors.of(context).moss,
        minimumSize: const Size.fromHeight(44),
        textStyle: const TextStyle(
          fontFamily: GuideType.sans,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.fieldKey,
    this.keyboard,
    this.formatters,
    this.obscure = false,
    this.autofill,
    this.maxLength,
    this.gap = true,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final bool obscure;
  final List<String>? autofill;
  final int? maxLength;
  final bool gap;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.rule),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: gap ? 10 : 0),
      child: SizedBox(
        height: 48,
        child: TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: keyboard,
          inputFormatters: formatters,
          obscureText: obscure,
          autofillHints: autofill,
          maxLength: maxLength,
          autocorrect: false,
          enableSuggestions: !obscure,
          cursorColor: colors.moss,
          style: TextStyle(color: colors.ink, fontSize: 16),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.ink3, fontSize: 16),
            filled: true,
            fillColor: colors.cream,
            // A dense outline hugs the text line and leaves this box empty.
            isDense: false,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.moss, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallingCode extends StatelessWidget {
  const _CallingCode({required this.code, required this.onPressed});

  final String code;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Material(
      color: colors.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('guideSignInCallingCode'),
        onTap: onPressed,
        child: SizedBox(
          width: 84,
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                code,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: colors.ink, fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: GuideColors.of(context).madder,
          fontSize: 14,
          height: 1.35,
        ),
      ),
    );
  }
}

class _Legal extends StatelessWidget {
  const _Legal({required this.onOpen});

  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final terms = strings.guide_sign_in_terms;
    final privacy = strings.guide_sign_in_privacy;
    final sentence = strings.guide_sign_in_legal(terms, privacy);
    final body = TextStyle(fontSize: 12, height: 1.45, color: colors.ink3);
    final link = body.copyWith(
      color: colors.moss,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: colors.moss,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text.rich(
        TextSpan(
          style: body,
          children: _spans(sentence, terms, privacy, link),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  List<InlineSpan> _spans(
    String sentence,
    String terms,
    String privacy,
    TextStyle link,
  ) {
    final termsAt = sentence.indexOf(terms);
    final privacyAt = sentence.indexOf(privacy);
    if (termsAt < 0 || privacyAt < 0) {
      return [TextSpan(text: sentence)];
    }
    final marks = <(int, String, String)>[
      (termsAt, terms, termsOfUseUrl),
      (privacyAt, privacy, privacyPolicyUrl),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final mark in marks) {
      if (mark.$1 > cursor) {
        spans.add(TextSpan(text: sentence.substring(cursor, mark.$1)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => onOpen(mark.$3),
            child: Text(mark.$2, style: link),
          ),
        ),
      );
      cursor = mark.$1 + mark.$2.length;
    }
    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor)));
    }
    return spans;
  }
}

class _AppleMark extends StatelessWidget {
  const _AppleMark(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _ApplePainter(color),
    );
  }
}

class _ApplePainter extends CustomPainter {
  _ApplePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.scale(scale, scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(_body(), paint);
    canvas.drawPath(_leaf(), paint);
  }

  Path _body() {
    return Path()
      ..moveTo(16.4, 12.6)
      ..relativeCubicTo(0, -2.5, 2, -3.6, 2.1, -3.7)
      ..relativeCubicTo(-1.2, -1.7, -3, -1.9, -3.6, -2)
      ..relativeCubicTo(-1.5, -0.2, -3, 0.9, -3.8, 0.9)
      ..relativeCubicTo(-0.8, 0, -2, -0.9, -3.3, -0.8)
      ..relativeCubicTo(-1.7, 0, -3.3, 1, -4.1, 2.5)
      ..relativeCubicTo(-1.8, 3.1, -0.5, 7.6, 1.3, 10.1)
      ..relativeCubicTo(0.8, 1.2, 1.8, 2.6, 3.1, 2.5)
      ..relativeCubicTo(1.3, 0, 1.7, -0.8, 3.3, -0.8)
      ..relativeCubicTo(1.5, 0, 1.9, 0.8, 3.3, 0.8)
      ..relativeCubicTo(1.4, 0, 2.2, -1.2, 3, -2.5)
      ..relativeCubicTo(1, -1.4, 1.3, -2.7, 1.4, -2.8)
      ..relativeCubicTo(-0.1, 0, -2.7, -1, -2.7, -4.2)
      ..close();
  }

  Path _leaf() {
    return Path()
      ..moveTo(13.9, 5.2)
      ..relativeCubicTo(0.7, -0.8, 1.2, -2, 1, -3.2)
      ..relativeCubicTo(-1, 0, -2.2, 0.7, -3, 1.5)
      ..relativeCubicTo(-0.6, 0.7, -1.2, 1.9, -1, 3.1)
      ..relativeCubicTo(1.1, 0.1, 2.3, -0.6, 3, -1.4)
      ..close();
  }

  @override
  bool shouldRepaint(_ApplePainter oldDelegate) => oldDelegate.color != color;
}

/// Calling-code list. Each code stays on one line. The stock picker locks
/// the code to 45px, which wraps +1684.
class _CallingCodeSheet extends StatefulWidget {
  const _CallingCodeSheet();

  @override
  State<_CallingCodeSheet> createState() => _CallingCodeSheetState();
}

class _CallingCodeSheetState extends State<_CallingCodeSheet> {
  final TextEditingController _query = TextEditingController();
  final List<Country> _all = CountryService().getAll();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _name(Country country) {
    final translated = country.getTranslatedName(context)?.trim();
    if (translated == null || translated.isEmpty) return country.name;
    return translated.replaceAll(RegExp(r'\s+'), ' ');
  }

  List<Country> _visible() {
    final query = _query.text.trim().toLowerCase();
    final digits = query.replaceAll(RegExp(r'\D'), '');
    final rows = <Country>[
      for (final country in _all)
        if (query.isEmpty ||
            _name(country).toLowerCase().contains(query) ||
            country.countryCode.toLowerCase().startsWith(query) ||
            (digits.isNotEmpty && country.phoneCode.startsWith(digits)))
          country,
    ];
    rows.sort((a, b) {
      final byName = _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
      if (byName != 0) return byName;
      return a.countryCode.compareTo(b.countryCode);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final media = MediaQuery.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.rule),
    );
    final rows = _visible();
    return Padding(
      padding: EdgeInsets.only(
        top: media.padding.top + 8,
        bottom: media.viewInsets.bottom,
      ),
      child: Material(
        color: colors.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: media.size.height -
              media.padding.top -
              media.viewInsets.bottom -
              8,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _query,
                    cursorColor: colors.moss,
                    style: TextStyle(color: colors.ink, fontSize: 16),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: strings.search,
                      hintStyle: TextStyle(color: colors.ink3, fontSize: 16),
                      filled: true,
                      fillColor: colors.cream,
                      isDense: false,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      border: border,
                      enabledBorder: border,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.moss, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(bottom: media.padding.bottom + 12),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final country = rows[index];
                    return InkWell(
                      onTap: () => Navigator.pop(context, country),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Text(
                              country.flagEmoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '+${country.phoneCode}',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(color: colors.ink, fontSize: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _name(country),
                                style: TextStyle(
                                  color: colors.ink,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
