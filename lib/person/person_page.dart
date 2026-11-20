import 'dart:async';

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/offline/offline_page.dart';
import 'package:abherbs_flutter/shell/ad_consent.dart';
import 'package:abherbs_flutter/shell/review_prompt.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/shell/guide_widgets.dart';
import 'package:abherbs_flutter/person/authentication.dart';
import 'package:abherbs_flutter/purchase/purchases.dart';
import 'package:abherbs_flutter/data/utils.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/intl.dart' hide TextDirection;

class GuidePersonPage extends StatefulWidget {
  final GuidePersonView? view;
  final Future<GuidePersonView> Function(Locale locale) load;
  final ValueChanged<GuideAppearance>? onAppearance;
  final Future<void> Function(BuildContext context)? onSignIn;
  final Future<void> Function(BuildContext context)? onSignOut;
  final Future<void> Function(BuildContext context)? onDeleteAccount;
  final Future<void> Function(BuildContext context)? onRestore;
  final Future<void> Function(BuildContext context)? onLanguage;
  final Future<void> Function(BuildContext context)? onFieldGuide;
  final Future<void> Function(BuildContext context)? onOffline;
  final Future<void> Function(BuildContext context)? onStatistics;
  final Future<void> Function()? onRate;
  final ValueChanged<int>? onSelectTab;

  /// When set, the page shows this build instead of reading the package.
  final String? versionName;
  final String? buildNumber;
  final Future<void> Function(String line)? onCopyVersion;

  const GuidePersonPage({
    super.key,
    this.view,
    this.load = loadGuidePerson,
    this.onAppearance,
    this.onSignIn,
    this.onSignOut,
    this.onDeleteAccount,
    this.onRestore,
    this.onLanguage,
    this.onFieldGuide,
    this.onOffline,
    this.onStatistics,
    this.onRate,
    this.onSelectTab,
    this.versionName,
    this.buildNumber,
    this.onCopyVersion,
  });

  @override
  State<GuidePersonPage> createState() => _GuidePersonPageState();
}

class _GuidePersonPageState extends State<GuidePersonPage> {
  GuidePersonView? _view;
  GuideAppearance _appearance = GuideAppearance.system;
  bool _appearanceChosen = false;
  bool _loading = true;
  bool _failed = false;
  String? _locale;
  int _ticket = 0;
  StreamSubscription<dynamic>? _authSub;
  StreamSubscription<DatabaseEvent>? _creditsSub;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  String? _versionName;
  String? _buildNumber;
  bool _adPrivacy = false;

  @override
  void initState() {
    super.initState();
    Purchases.namesRevision.addListener(_onPlan);
    unawaited(_loadAdPrivacy());
    _versionName = widget.versionName;
    _buildNumber = widget.buildNumber;
    if (widget.versionName == null && widget.buildNumber == null) {
      unawaited(_loadAppVersion());
    }
    final initial = widget.view;
    if (initial != null) {
      _view = initial;
      _appearance = initial.appearance;
      _loading = false;
      GuideAppearanceController.instance.apply(initial.appearance);
      return;
    }
    _appearance = GuideAppearanceController.instance.appearance;
    _authSub = Auth.subscribe((user) {
      unawaited(_onAccount(user != null));
    });
    _watchCredits();
    _purchaseSub = InAppPurchase.instance.purchaseStream.listen(
      (purchases) {
        final changed = purchases.any((purchase) {
          return purchase.status == PurchaseStatus.restored ||
              purchase.status == PurchaseStatus.purchased;
        });
        if (changed) _reload();
      },
      onError: (Object error) => debugPrint('guide person: $error'),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.view != null) return;
    final code = Localizations.localeOf(context).toString();
    if (_locale == code) return;
    _locale = code;
    _reload();
  }

  @override
  void didUpdateWidget(GuidePersonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final view = widget.view;
    if (view != null && view != oldWidget.view) {
      _view = view;
      _appearance = view.appearance;
      _appearanceChosen = false;
      _loading = false;
      _failed = false;
      GuideAppearanceController.instance.apply(view.appearance);
    }
    if (widget.versionName != oldWidget.versionName ||
        widget.buildNumber != oldWidget.buildNumber) {
      _versionName = widget.versionName;
      _buildNumber = widget.buildNumber;
    }
  }

  Future<void> _loadAdPrivacy() async {
    final show = await adPrivacyOptionsRequired();
    if (!mounted || !show || _adPrivacy) return;
    setState(() => _adPrivacy = true);
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionName = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (error) {
      debugPrint('guide version: $error');
    }
  }

  Future<void> _rate() async {
    final rate = widget.onRate;
    if (rate != null) {
      await rate();
      return;
    }
    await openWriteReview();
  }

  Future<void> _copyVersion(String line) async {
    final copy = widget.onCopyVersion;
    if (copy != null) {
      await copy(line);
      return;
    }
    await Clipboard.setData(ClipboardData(text: line));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(line)));
  }

  Widget? _versionFooter(BuildContext context) {
    final line = guideVersionLine(
      label: S.of(context).version,
      version: _versionName ?? '',
      build: _buildNumber ?? '',
    );
    if (line.isEmpty) return null;
    final colors = GuideColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Center(
        child: TextButton(
          key: const Key('guide-version'),
          onPressed: () => unawaited(_copyVersion(line)),
          style: TextButton.styleFrom(
            foregroundColor: colors.ink3,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontFamily: GuideType.sans,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Text(line),
        ),
      ),
    );
  }

  @override
  void dispose() {
    Purchases.namesRevision.removeListener(_onPlan);
    _authSub?.cancel();
    _creditsSub?.cancel();
    _purchaseSub?.cancel();
    super.dispose();
  }

  /// The account plan can arrive after this page has drawn the free card.
  void _onPlan() {
    if (!mounted || widget.view != null) return;
    unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!mounted || widget.view != null) return;
    final ticket = ++_ticket;
    try {
      final view = await widget.load(Localizations.localeOf(context));
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _view = view;
        _failed = false;
        _loading = false;
        if (!_appearanceChosen) _appearance = view.appearance;
      });
      if (!_appearanceChosen) {
        GuideAppearanceController.instance.apply(view.appearance);
      }
    } catch (error) {
      debugPrint('guide person: $error');
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _onAccount(bool signedIn) async {
    if (widget.view != null) return;
    if (signedIn) {
      try {
        await Auth.setUser();
      } catch (error) {
        debugPrint('guide person: $error');
      }
    }
    if (!mounted || widget.view != null) return;
    _watchCredits();
    await _reload();
  }

  void _watchCredits() {
    _creditsSub?.cancel();
    _creditsSub = null;
    final uid = Auth.appUser?.uid;
    if (uid == null) return;
    _creditsSub = usersReference
        .child(uid)
        .child(firebaseAttributeCredits)
        .onValue
        .listen(
      (event) {
        final value = event.snapshot.value;
        final next = value is int ? value : (value is num ? value.toInt() : 0);
        if (Auth.credits == next) return;
        Auth.credits = next;
        _reload();
      },
      onError: (Object error) => debugPrint('guide person: $error'),
    );
  }

  Future<void> _act(Future<void> Function(BuildContext context)? action) async {
    if (action == null) return;
    await action(context);
    if (!mounted || widget.view != null) return;
    await _reload();
  }

  void _choose(GuideAppearance next) {
    setState(() {
      _appearance = next;
      _appearanceChosen = true;
    });
    final custom = widget.onAppearance;
    if (custom != null) {
      GuideAppearanceController.instance.apply(next);
      custom(next);
      return;
    }
    unawaited(saveGuideAppearance(next));
  }

  void _selectTab(int index) {
    final select = widget.onSelectTab;
    if (select != null) {
      select(index);
      return;
    }
    GuideTabs.show?.call(index);
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return GuideTheme(
      navigationColor: (colors) => colors.cream,
      child: Builder(
        builder: (context) {
          return guideChromeFrame(
            context,
            index: 0,
            personOn: true,
            onSelect: _selectTab,
            child: SafeArea(
              bottom: GuideWindow.of(context).wide,
              child: GuideReadable(child: _body(context)),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuideBackButton(label: strings.guide_back),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.moss,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_failed || _view == null) {
      final version = _versionFooter(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuideBackButton(label: strings.guide_back),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.guide_person_failed,
                    style: TextStyle(color: colors.ink2),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _reload,
                    child: Text(strings.guide_results_retry),
                  ),
                ],
              ),
            ),
          ),
          if (version != null) version,
        ],
      );
    }
    return _content(context, _view!);
  }

  Widget _content(BuildContext context, GuidePersonView view) {
    final strings = S.of(context);
    final account = view.account;
    final version = _versionFooter(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        GuideBackButton(label: strings.guide_back),
        if (account != null)
          _AccountHeader(
            lines: guideAccountLines(
              name: account.name,
              email: account.email,
              phone: account.phone,
              provider: account.provider,
              yourAccount: strings.guide_person_your_account,
              signedIn: strings.guide_person_signed_in,
              google: strings.guide_person_google,
              apple: strings.guide_person_apple,
              emailPassword: strings.guide_person_email_password,
              phoneLabel: strings.guide_person_phone,
              appleHidden: strings.guide_person_apple_hidden,
            ),
          ),
        _AllowanceCard(
          allowance: view.allowance,
          onSignIn: account == null && widget.onSignIn != null
              ? () => _act(widget.onSignIn)
              : null,
          onFieldGuide: view.allowance.fieldGuide && widget.onFieldGuide != null
              ? () => _act(widget.onFieldGuide)
              : null,
        ),
        const SizedBox(height: 4),
        if (view.showFieldGuide && !view.allowance.fieldGuide)
          _MenuRow(
            icon: Icons.eco_outlined,
            title: strings.guide_person_field_guide,
            subtitle: strings.guide_person_field_guide_perks,
            onPressed: widget.onFieldGuide == null
                ? null
                : () => _act(widget.onFieldGuide),
          ),
        _MenuRow(
          icon: Icons.restore,
          title: strings.guide_person_restore,
          subtitle: strings.guide_person_restore_note,
          onPressed:
              widget.onRestore == null ? null : () => _act(widget.onRestore),
        ),
        _LanguageRow(
          name: view.languageName,
          onPressed:
              widget.onLanguage == null ? null : () => _act(widget.onLanguage),
        ),
        _ThemeRow(
          appearance: _appearance,
          onChoose: _choose,
        ),
        if (_adPrivacy)
          _MenuRow(
            icon: Icons.privacy_tip_outlined,
            title: strings.guide_ad_privacy,
            subtitle: strings.guide_ad_privacy_note,
            onPressed: () => unawaited(showAdPrivacyOptions()),
          ),
        if (view.showOffline)
          _MenuRow(
            icon: Icons.cloud_outlined,
            title: view.offlineHold == null
                ? strings.offline_title
                : strings.guide_offline_title,
            subtitle: view.offlineHold == null
                ? (view.offlineOn
                    ? strings.guide_person_offline_on
                    : strings.offline_subtitle)
                : guideOfflineMenuText(context, view.offlineHold),
            onPressed:
                widget.onOffline == null ? null : () => _act(widget.onOffline),
          ),
        _MenuRow(
          icon: Icons.bar_chart_outlined,
          title: strings.observation_stats,
          subtitle: strings.guide_stats_menu,
          onPressed: widget.onStatistics == null
              ? null
              : () => _act(widget.onStatistics),
        ),
        _MenuRow(
          rowKey: const Key('guide-rate'),
          icon: Icons.star_outline,
          title: strings.guide_person_rate,
          subtitle: strings.guide_person_rate_note,
          onPressed: () => unawaited(_rate()),
        ),
        if (account != null) ...[
          _MenuRow(
            icon: Icons.person_outline,
            title: strings.auth_sign_out,
            subtitle: strings.guide_person_sign_out_note,
            onPressed:
                widget.onSignOut == null ? null : () => _act(widget.onSignOut),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 6),
            child: Text(
              strings.guide_person_danger_zone,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: GuideColors.of(context).ink3,
                height: 1.2,
              ),
            ),
          ),
          _MenuRow(
            icon: Icons.delete_outline,
            title: strings.auth_delete_account,
            subtitle: strings.guide_person_delete_note,
            danger: true,
            onPressed: widget.onDeleteAccount == null
                ? null
                : () => _act(widget.onDeleteAccount),
          ),
        ],
        if (version != null) version,
      ],
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final GuideAccountLines lines;

  const _AccountHeader({required this.lines});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final avatar = lines.phoneAvatar
        ? const Icon(Icons.smartphone_outlined, color: Colors.white, size: 24)
        : lines.initial.isEmpty
            ? const Icon(Icons.person, color: Colors.white, size: 26)
            : Text(
                lines.initial,
                style: const TextStyle(
                  fontFamily: GuideType.serif,
                  fontSize: 24,
                  color: Colors.white,
                  height: 1,
                ),
              );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 20, 14),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.gold,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 54,
              height: 54,
              child: Center(child: avatar),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lines.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                Text(
                  lines.detail,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.ink3,
                    height: 1.4,
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

class _AllowanceCard extends StatelessWidget {
  final GuideAllowance allowance;
  final VoidCallback? onSignIn;
  final VoidCallback? onFieldGuide;

  const _AllowanceCard({
    required this.allowance,
    required this.onSignIn,
    this.onFieldGuide,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
      child: Material(
        color: colors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: allowance.fieldGuide ? onFieldGuide : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _cardBody(context, strings, colors),
          ),
        ),
      ),
    );
  }

  Widget _cardBody(BuildContext context, S strings, GuideColors colors) {
    final body = switch (allowance.kind) {
      GuideAllowanceKind.guest => allowance.namesLeft > 0
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.guide_person_names_left, style: _title(colors)),
                const SizedBox(height: 10),
                _AllowanceBar(allowance: allowance),
                const SizedBox(height: 6),
                Text(
                  strings.guide_meter_left(allowance.namesLeft),
                  style: _note(colors),
                ),
                const SizedBox(height: 4),
                Text(strings.guide_person_guest_body, style: _note(colors)),
                const SizedBox(height: 10),
                _SignInButton(onPressed: onSignIn),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.guide_meter_sign_in,
                  style: _title(colors),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.guide_person_guest_body,
                  style: _note(colors),
                ),
                const SizedBox(height: 10),
                _SignInButton(onPressed: onSignIn),
              ],
            ),
      GuideAllowanceKind.month => _month(context, strings, colors),
      GuideAllowanceKind.credits => _credits(strings, colors),
      GuideAllowanceKind.unlimited => _unlimited(strings, colors),
    };
    // Store purchases stay after sign-out, so this card is not the guest card.
    if (allowance.kind == GuideAllowanceKind.guest || onSignIn == null) {
      return body;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: 10),
        _SignInButton(onPressed: onSignIn),
      ],
    );
  }

  Widget _month(BuildContext context, S strings, GuideColors colors) {
    final resets = allowance.resetsOn;
    final date = resets == null
        ? ''
        : DateFormat.MMMd(Localizations.localeOf(context).toString())
            .format(resets);
    final more = guideMonthAdsLeft(allowance);
    final String detail;
    if (allowance.extraUsed <= 0) {
      detail = strings.guide_person_month_used(allowance.includedUsed);
    } else if (more <= 0) {
      detail = strings.guide_person_month_used_extra_done(
        allowance.includedUsed,
        allowance.extraUsed,
      );
    } else {
      detail = strings.guide_person_month_used_extra(
        allowance.includedUsed,
        allowance.extraUsed,
        more,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child:
                  Text(strings.guide_person_names_month, style: _title(colors)),
            ),
            Text(strings.guide_person_resets(date), style: _note(colors)),
          ],
        ),
        const SizedBox(height: 10),
        _AllowanceBar(allowance: allowance),
        const SizedBox(height: 6),
        Text(detail, style: _note(colors)),
        if (allowance.seenSynced) ...[
          const SizedBox(height: 4),
          Text(strings.guide_person_seen_synced, style: _note(colors)),
        ],
      ],
    );
  }

  Widget _credits(S strings, GuideColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.guide_person_names_left, style: _title(colors)),
        const SizedBox(height: 10),
        _AllowanceBar(allowance: allowance),
        const SizedBox(height: 6),
        Text(
          strings.guide_meter_left(allowance.namesLeft),
          style: _note(colors),
        ),
      ],
    );
  }

  Widget _unlimited(S strings, GuideColors colors) {
    final detail = allowance.fieldGuide
        ? strings.guide_person_field_guide_perks
        : guideFieldGuideDetail(
            unlimitedNames: allowance.unlimitedNames,
            noAds: allowance.noAds,
            seenSynced: allowance.seenSynced,
            unlimited: strings.guide_person_unlimited,
            noAdsLabel: strings.guide_person_no_ads,
            seenSyncedLabel: strings.guide_person_seen_synced,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          allowance.fieldGuide
              ? strings.guide_person_field_guide
              : strings.guide_person_unlimited,
          style: _title(colors),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(detail, style: _note(colors)),
        ],
      ],
    );
  }

  TextStyle _title(GuideColors colors) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: colors.ink,
      height: 1.25,
    );
  }

  TextStyle _note(GuideColors colors) {
    return TextStyle(fontSize: 12, color: colors.ink3, height: 1.35);
  }
}

class _SignInButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _SignInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        color: colors.mossFill,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: SizedBox(
              height: 34,
              child: Center(
                child: Text(
                  S.of(context).auth_sign_in,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AllowanceBar extends StatelessWidget {
  final GuideAllowance allowance;

  const _AllowanceBar({required this.allowance});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final shares = guideAllowanceBarShares(allowance);
    final parts = <Widget>[
      if (shares.included > 0)
        Expanded(
          flex: shares.included,
          child: ColoredBox(color: colors.mossFill),
        ),
      if (shares.extra > 0)
        Expanded(
          flex: shares.extra,
          child: ColoredBox(color: colors.gold),
        ),
      if (shares.rest > 0)
        Expanded(
          flex: shares.rest,
          child: ColoredBox(color: colors.paper2),
        ),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        width: double.infinity,
        child: Row(children: parts),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final Key? rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;
  final bool danger;

  const _MenuRow({
    this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final tone = danger ? colors.madder : colors.moss;
    final titleColor = danger ? colors.madder : colors.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: InkWell(
        key: rowKey,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.ink3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  final String name;
  final VoidCallback? onPressed;

  const _LanguageRow({required this.name, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final forward = Directionality.of(context) == TextDirection.rtl
        ? Icons.chevron_left
        : Icons.chevron_right;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 8, 14),
          child: Row(
            children: [
              Icon(Icons.language, size: 22, color: colors.moss),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.guide_person_language,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colors.ink2,
                    height: 1.2,
                  ),
                ),
              ),
              if (onPressed != null) ...[
                const SizedBox(width: 2),
                Icon(forward, size: 22, color: colors.ink3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final GuideAppearance appearance;
  final ValueChanged<GuideAppearance> onChoose;

  const _ThemeRow({required this.appearance, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    final strings = S.of(context);
    final platform = MediaQuery.platformBrightnessOf(context);
    final detail = guideThemeDetail(
      appearance: appearance,
      platform: platform,
      alwaysLight: strings.guide_person_theme_light,
      alwaysDark: strings.guide_person_theme_dark,
      likePhoneLight: strings.guide_person_theme_system_light,
      likePhoneDark: strings.guide_person_theme_system_dark,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 12, 10),
        child: Row(
          children: [
            Icon(Icons.contrast, size: 22, color: colors.moss),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.guide_person_theme,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(
                        fontSize: 13, color: colors.ink3, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ThemeSegment(appearance: appearance, onChoose: onChoose),
          ],
        ),
      ),
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  final GuideAppearance appearance;
  final ValueChanged<GuideAppearance> onChoose;

  const _ThemeSegment({required this.appearance, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final choices = [
      (GuideAppearance.light, strings.guide_person_light),
      (GuideAppearance.dark, strings.guide_person_dark),
      (GuideAppearance.system, strings.guide_person_system),
    ];
    final colors = GuideColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cream,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colors.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            _ThemeChoice(
              label: choice.$2,
              selected: appearance == choice.$1,
              onPressed: () => onChoose(choice.$1),
            ),
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _ThemeChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = GuideColors.of(context);
    return Material(
      color: selected ? colors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            height: 28,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? colors.onInk : colors.ink3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
