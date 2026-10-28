import 'dart:ui' show Tristate;

import 'package:abherbs_flutter/generated/l10n.dart';
import 'package:abherbs_flutter/person/guide_person.dart';
import 'package:abherbs_flutter/shell/guide_theme.dart';
import 'package:abherbs_flutter/person/person_page.dart';
import 'package:abherbs_flutter/person/setting_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    GuideAppearanceController.instance.resetForTest();
  });

  tearDown(() {
    GuideAppearanceController.instance.resetForTest();
  });

  test('the version line keeps the name and the build number', () {
    expect(
      guideVersionLine(label: 'Version', version: '9.0.0', build: '900'),
      'Version 9.0.0 (900)',
    );
    expect(
      guideVersionLine(label: 'Verzia', version: ' 9.0.0 ', build: '900'),
      'Verzia 9.0.0 (900)',
    );
    expect(
      guideVersionLine(label: 'Version', version: '9.0.0', build: ''),
      'Version 9.0.0',
    );
    expect(
      guideVersionLine(label: 'Version', version: '', build: ''),
      '',
    );
  });

  test('a signed-in account keeps the provider and the trimmed name', () {
    expect(
      guideAccountProvider(['password', 'google.com']),
      GuideAccountProvider.google,
    );
    expect(guideAccountProvider(['phone']), GuideAccountProvider.phone);
    expect(guideAccountProvider(['apple.com']), GuideAccountProvider.apple);
    expect(guideAccountFrom(signedIn: false), isNull);
    expect(
      guideAccountFrom(
        signedIn: true,
        displayName: ' Ada ',
        email: 'ada@example.com',
        providerIds: const ['google.com'],
      ),
      isA<GuidePersonAccount>()
          .having((account) => account.name, 'name', 'Ada')
          .having((account) => account.email, 'email', 'ada@example.com')
          .having(
            (account) => account.provider,
            'provider',
            GuideAccountProvider.google,
          ),
    );
  });

  test('the account header shows the name, then the address, then the phone',
      () {
    const copy = (
      yourAccount: 'Your account',
      signedIn: 'Signed in',
      google: 'Google',
      apple: 'Apple',
      emailPassword: 'Email and password',
      phoneLabel: 'Phone',
      appleHidden: 'Email hidden by Apple',
    );

    final google = guideAccountLines(
      name: 'Anna Novák',
      email: 'anna.novak@gmail.com',
      provider: GuideAccountProvider.google,
      yourAccount: copy.yourAccount,
      signedIn: copy.signedIn,
      google: copy.google,
      apple: copy.apple,
      emailPassword: copy.emailPassword,
      phoneLabel: copy.phoneLabel,
      appleHidden: copy.appleHidden,
    );
    expect(google.title, 'Anna Novák');
    expect(google.detail, 'anna.novak@gmail.com · Google');
    expect(google.initial, 'A');
    expect(google.phoneAvatar, isFalse);

    final apple = guideAccountLines(
      name: 'Anna Novák',
      email: 'abc@privaterelay.appleid.com',
      provider: GuideAccountProvider.apple,
      yourAccount: copy.yourAccount,
      signedIn: copy.signedIn,
      google: copy.google,
      apple: copy.apple,
      emailPassword: copy.emailPassword,
      phoneLabel: copy.phoneLabel,
      appleHidden: copy.appleHidden,
    );
    expect(apple.detail, 'Email hidden by Apple');

    final appleMail = guideAccountLines(
      name: 'Anna Novák',
      email: 'anna@icloud.com',
      provider: GuideAccountProvider.apple,
      yourAccount: copy.yourAccount,
      signedIn: copy.signedIn,
      google: copy.google,
      apple: copy.apple,
      emailPassword: copy.emailPassword,
      phoneLabel: copy.phoneLabel,
      appleHidden: copy.appleHidden,
    );
    expect(appleMail.detail, 'anna@icloud.com · Apple');

    final email = guideAccountLines(
      email: 'anna.novak@example.com',
      provider: GuideAccountProvider.email,
      yourAccount: copy.yourAccount,
      signedIn: copy.signedIn,
      google: copy.google,
      apple: copy.apple,
      emailPassword: copy.emailPassword,
      phoneLabel: copy.phoneLabel,
      appleHidden: copy.appleHidden,
    );
    expect(email.title, 'anna.novak@example.com');
    expect(email.detail, 'Email and password');
    expect(email.initial, 'A');

    final phone = guideAccountLines(
      phone: '+421905123456',
      provider: GuideAccountProvider.phone,
      yourAccount: copy.yourAccount,
      signedIn: copy.signedIn,
      google: copy.google,
      apple: copy.apple,
      emailPassword: copy.emailPassword,
      phoneLabel: copy.phoneLabel,
      appleHidden: copy.appleHidden,
    );
    expect(phone.title, '+421905123456');
    expect(phone.detail, 'Phone');
    expect(phone.phoneAvatar, isTrue);
    expect(phone.initial, isEmpty);

    final all = guideAccountLines(
      name: 'Anna Novák',
      email: 'anna.novak@gmail.com',
      phone: '+421905123456',
      provider: GuideAccountProvider.google,
      yourAccount: copy.yourAccount,
      signedIn: copy.signedIn,
      google: copy.google,
      apple: copy.apple,
      emailPassword: copy.emailPassword,
      phoneLabel: copy.phoneLabel,
      appleHidden: copy.appleHidden,
    );
    expect(all.detail, 'anna.novak@gmail.com · +421905123456 · Google');
  });

  test('language follows the saved choice, then this phone', () {
    expect(
      guideLanguageName(languages, 'de_DE', const Locale('en', 'US')),
      'Deutsch',
    );
    expect(
      guideLanguageName(languages, '', const Locale('en', 'US')),
      'English',
    );
    expect(guideLanguageName(languages, '', const Locale('nn')), 'Norsk');
    expect(guideLanguageName(languages, '', const Locale('zh')), '中文');
  });

  test('the month bar counts five included names and five from ads', () {
    final month = GuideAllowance.month(
      used: 6,
      fromAds: 1,
      now: DateTime(2026, 9, 30),
    );
    expect(month.includedUsed, 5);
    expect(month.extraUsed, 1);
    expect(guideMonthAdsLeft(month), 4);
    expect(month.resetsOn, DateTime(2026, 10, 1));
    expect(guideAllowanceBarShares(month), (included: 5, extra: 1, rest: 4));

    final december = GuideAllowance.month(
      used: 2,
      fromAds: 0,
      now: DateTime(2026, 12, 15),
    );
    expect(december.resetsOn, DateTime(2027, 1, 1));
    expect(guideMonthAdsLeft(december), 5);
    expect(
      guideAllowanceBarShares(december),
      (included: 2, extra: 0, rest: 8),
    );
    expect(
      guideMonthAdsLeft(GuideAllowance.month(
        used: 10,
        fromAds: 5,
        now: DateTime(2026, 9, 30),
      )),
      0,
    );

    final credits = GuideAllowance.credits(3);
    expect(guideAllowanceBarShares(credits), (included: 3, extra: 0, rest: 2));
    expect(
      guideAllowanceBarShares(GuideAllowance.credits(12)),
      (included: 5, extra: 0, rest: 0),
    );
    expect(
      guideAllowanceBarShares(const GuideAllowance.guest(free: true)),
      (included: 1, extra: 0, rest: 0),
    );
  });

  test('a photo-storage plan is Field Guide and a free account has five names',
      () {
    final subscribed = guideLiveAllowance(
      signedIn: true,
      subscribed: true,
      unlimitedNames: true,
      noAds: true,
      seenSynced: true,
      now: DateTime(2026, 9, 30),
    );
    expect(subscribed.kind, GuideAllowanceKind.unlimited);
    expect(subscribed.fieldGuide, isTrue);
    expect(
      guideFieldGuideDetail(
        unlimitedNames: true,
        noAds: true,
        seenSynced: true,
        unlimited: 'Unlimited names',
        noAdsLabel: 'no ads',
        seenSyncedLabel: 'Seen synced',
      ),
      'Unlimited names · no ads · Seen synced',
    );
    expect(
      guidePersonFieldGuideOffer(
        trial: '7 days free',
        perks: 'Unlimited • No Ads • Seen sync • Offline',
      ),
      '7 days free • Unlimited • No Ads • Seen sync • Offline',
    );

    final names = guideLiveAllowance(
      signedIn: true,
      subscribed: false,
      unlimitedNames: true,
      noAds: false,
      seenSynced: false,
      now: DateTime(2026, 9, 30),
    );
    expect(names.fieldGuide, isFalse);
    expect(names.unlimitedNames, isTrue);

    final left = guideLiveAllowance(
      signedIn: true,
      subscribed: false,
      unlimitedNames: false,
      noAds: false,
      seenSynced: true,
      now: DateTime(2026, 9, 30),
    );
    expect(left.kind, GuideAllowanceKind.month);
    expect(left.includedUsed, 0);
    expect(left.namesLeft, 5);
    expect(left.seenSynced, isTrue);
    expect(left.fieldGuide, isFalse);
    expect(left.noAds, isFalse);

    final banked = guideLiveAllowance(
      signedIn: true,
      subscribed: false,
      unlimitedNames: false,
      noAds: false,
      seenSynced: false,
      usedThisMonth: 5,
      extraFromAds: 1,
      now: DateTime(2026, 9, 30),
    );
    expect(banked.namesLeft, 1);
    expect(banked.includedUsed, 5);

    final guest = guideLiveAllowance(
      signedIn: false,
      subscribed: false,
      unlimitedNames: false,
      noAds: false,
      seenSynced: false,
      now: DateTime(2026, 9, 30),
    );
    expect(guest.kind, GuideAllowanceKind.guest);

    final kept = guideLiveAllowance(
      signedIn: false,
      subscribed: true,
      unlimitedNames: true,
      noAds: true,
      seenSynced: true,
      now: DateTime(2026, 9, 30),
    );
    expect(kept.kind, GuideAllowanceKind.unlimited);
    expect(kept.fieldGuide, isTrue);

    final counted = guideLiveAllowance(
      signedIn: true,
      subscribed: false,
      unlimitedNames: false,
      noAds: false,
      seenSynced: false,
      usedThisMonth: 2,
      extraFromAds: 1,
      now: DateTime(2026, 9, 30),
    );
    expect(counted.kind, GuideAllowanceKind.month);
    expect(counted.includedUsed, 2);
    expect(counted.extraUsed, 1);
    expect(counted.namesLeft, 4);
  });

  test('a null quota event does not apply', () {
    final now = DateTime.utc(2026, 10, 22);
    expect(guideMonthCountArrived(null, now), isNull);
    expect(guideMonthCountArrived('late', now), isNull);

    const previous = GuideMonthCount(namesUsed: 5, adGrants: 1);
    final line = guideMonthCountLine('account', previous, now);
    expect(
      guideMonthCountForAccount(uid: 'account', stored: line, now: now),
      previous,
    );
    expect(
      guideMonthCountForAccount(uid: 'other', stored: line, now: now),
      GuideMonthCount.empty,
    );
    expect(
      guideMonthCountForAccount(uid: null, stored: line, now: now),
      GuideMonthCount.empty,
    );
  });

  test('a missed quota read keeps the last count, including an ad name', () {
    final line = guideMonthCountLine(
      'account',
      const GuideMonthCount(namesUsed: 5, adGrants: 1),
      DateTime.utc(2026, 10, 21),
    );
    final recalled = guideRecallMonthCount(
      line,
      uid: 'account',
      now: DateTime.utc(2026, 10, 21, 18),
    );
    expect(recalled, const GuideMonthCount(namesUsed: 5, adGrants: 1));
    final allowance = guideLiveAllowance(
      signedIn: true,
      subscribed: false,
      unlimitedNames: false,
      noAds: false,
      seenSynced: false,
      usedThisMonth: recalled!.namesUsed,
      extraFromAds: recalled.adGrants,
      now: DateTime.utc(2026, 10, 21),
    );
    expect(allowance.namesLeft, 1);
    expect(allowance.extraUsed, 1);

    expect(
      guideRecallMonthCount(
        line,
        uid: 'other',
        now: DateTime.utc(2026, 10, 21),
      ),
      isNull,
    );
    expect(
      guideRecallMonthCount(
        line,
        uid: 'account',
        now: DateTime.utc(2026, 11, 1),
      ),
      isNull,
    );
  });

  test('a stored month that is not this month counts as unused', () {
    final stale = guideMonthCountFrom(
      {'month': '2026-09', 'namesUsed': 5, 'adGrants': 2},
      DateTime.utc(2026, 10, 2),
    );
    expect(stale, GuideMonthCount.empty);

    final current = guideMonthCountFrom(
      {'month': '2026-10', 'namesUsed': 3, 'adGrants': 1},
      DateTime.utc(2026, 10, 2, 23),
    );
    expect(current.namesUsed, 3);
    expect(current.adGrants, 1);
    expect(guideQuotaMonth(DateTime.utc(2026, 10, 2, 23)), '2026-10');
  });

  test('theme words follow the choice and the phone', () {
    expect(
      guideThemeDetail(
        appearance: GuideAppearance.system,
        platform: Brightness.dark,
        alwaysLight: 'Always light',
        alwaysDark: 'Always dark',
        likePhoneLight: 'Light, like the phone',
        likePhoneDark: 'Dark, like the phone',
      ),
      'Dark, like the phone',
    );
    expect(
      guideResolvedBrightness(GuideAppearance.light, Brightness.dark),
      Brightness.light,
    );
    expect(guideAppearanceFromStore('dark'), GuideAppearance.dark);
    expect(guideAppearanceFromStore(''), GuideAppearance.system);
    expect(guideAppearanceStoreValue(GuideAppearance.system), isNull);
  });

  testWidgets('Account leaves Find, Book, and Seen unselected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_page(view: _guest())));

    for (final label in ['Find', 'Book', 'Seen']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontWeight, FontWeight.w400, reason: label);
      expect(text.style?.color, isNot(GuideColors.light.moss), reason: label);
    }
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Find, Tab 1 of 3'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Book, Tab 2 of 3'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Seen, Tab 3 of 3'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  testWidgets('a signed-out person can sign in', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var signed = 0;
    var guide = 0;
    await tester.pumpWidget(_app(_page(
      view: _guest(),
      onSignIn: (_) async => signed++,
      onFieldGuide: (_) async => guide++,
    )));

    expect(find.text('Sign in to name a photo'), findsOneWidget);
    expect(find.text('1 name left'), findsNothing);
    expect(find.text('Your account'), findsNothing);
    expect(
      find.text('7 days free • Unlimited • No Ads • Seen sync • Offline'),
      findsOneWidget,
    );
    expect(find.text('Delete account'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.tap(find.text('Field Guide'));
    expect(signed, 1);
    expect(guide, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a first open shows the one free photo name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_page(
      view: const GuidePersonView(
        account: null,
        allowance: GuideAllowance.guest(free: true),
        languageName: 'English',
        appearance: GuideAppearance.system,
        showFieldGuide: true,
        showOffline: false,
        offlineOn: false,
      ),
    )));

    expect(find.text('Names left'), findsOneWidget);
    expect(find.text('1 name left'), findsOneWidget);
    expect(find.text('Sign in to name a photo'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-in person sees the month, language, and theme',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    GuideAppearance? chosen;
    var restored = 0;
    var language = 0;
    var tab = -1;
    await tester.pumpWidget(_app(_page(
      view: _month(),
      onAppearance: (appearance) => chosen = appearance,
      onRestore: (_) async => restored++,
      onLanguage: (_) async => language++,
      onSelectTab: (index) => tab = index,
    )));

    expect(find.text('Anna Novák'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('anna.novak@gmail.com · Google'), findsOneWidget);
    expect(find.text('Your account'), findsNothing);
    expect(find.text('Names this month'), findsOneWidget);
    expect(find.text('Resets Oct 1'), findsOneWidget);
    expect(
      find.text('2 of 5 included used, 1 from ads. Up to 4 more from ads.'),
      findsOneWidget,
    );
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Light, like the phone'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(chosen, GuideAppearance.dark);
    expect(find.text('Always dark'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Theme'))).scaffoldBackgroundColor,
      GuideColors.dark.paper,
    );

    await tester.tap(find.text('Restore purchases'));
    await tester.tap(find.text('Language'));
    await tester.tap(find.text('Book'));
    expect(restored, 1);
    expect(language, 1);
    expect(tab, 1);

    await tester.scrollUntilVisible(
      find.byKey(const Key('guide-version')),
      80,
    );
    expect(find.text('Version 9.0.0 (900)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ad names already used come off the five still offered',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    GuidePersonView month({required int used, required int fromAds}) {
      return GuidePersonView(
        account: const GuidePersonAccount(
          name: 'Anna Novák',
          email: 'anna.novak@gmail.com',
          provider: GuideAccountProvider.google,
        ),
        allowance: GuideAllowance.month(
          used: used,
          fromAds: fromAds,
          now: DateTime(2026, 9, 30),
        ),
        languageName: 'English',
        appearance: GuideAppearance.system,
        showFieldGuide: false,
        showOffline: false,
        offlineOn: false,
      );
    }

    await tester.pumpWidget(_app(_page(view: month(used: 6, fromAds: 1))));
    expect(
      find.text('5 of 5 included used, 1 from ads. Up to 4 more from ads.'),
      findsOneWidget,
    );

    await tester.pumpWidget(_app(_page(view: month(used: 10, fromAds: 5))));
    expect(find.text('5 of 5 included used, 5 from ads.'), findsOneWidget);
    expect(find.textContaining('more from ads'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Field Guide stays on the list and can sign out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var signedOut = 0;
    var deleted = 0;
    var guide = 0;
    await tester.pumpWidget(_app(_page(
      view: _fieldGuide(),
      onSignOut: (_) async => signedOut++,
      onDeleteAccount: (_) async => deleted++,
      onFieldGuide: (_) async => guide++,
    )));

    expect(find.text('Field Guide'), findsOneWidget);
    expect(
      find.text('Unlimited • No Ads • Seen sync • Offline'),
      findsOneWidget,
    );
    expect(find.text('Dangerous zone'), findsOneWidget);
    expect(
      find.text('Subscribed · Unlimited sightings · no ads · Seen synced'),
      findsNothing,
    );
    expect(
      find.text('7 days free • Unlimited • No Ads • Seen sync • Offline'),
      findsNothing,
    );
    await tester.tap(find.text('Field Guide'));
    expect(guide, 1);
    expect(find.text('Finds stay on your account'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(
      find.text('Removes the account, finds, and photos'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('Delete account')).style?.color,
      GuideColors.light.madder,
    );
    await tester.tap(find.text('Sign out'));
    await tester.ensureVisible(find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    expect(signedOut, 1);
    expect(deleted, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a purchase kept after sign-out still offers Sign in',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var signed = 0;
    await tester.pumpWidget(_app(_page(
      view: const GuidePersonView(
        account: null,
        allowance: GuideAllowance.unlimited(
          fieldGuide: true,
          unlimitedNames: true,
          noAds: true,
          seenSynced: true,
        ),
        languageName: 'English',
        appearance: GuideAppearance.system,
        showFieldGuide: false,
        showOffline: false,
        offlineOn: false,
      ),
      onSignIn: (_) async => signed++,
    )));

    expect(find.text('Field Guide'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    expect(signed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the version copies the line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    await tester.pumpWidget(_app(_page(
      view: _guest(),
      onCopyVersion: (line) async => copied = line,
    )));

    await tester.ensureVisible(find.byKey(const Key('guide-version')));
    await tester.tap(find.byKey(const Key('guide-version')));
    expect(copied, 'Version 9.0.0 (900)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rate opens the store page from the row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var rated = 0;
    await tester.pumpWidget(_app(_page(
      view: _guest(),
      onRate: () async => rated++,
    )));

    await tester.ensureVisible(find.byKey(const Key('guide-rate')));
    expect(find.text('Rate this app'), findsOneWidget);
    expect(find.text('Opens the store page'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-rate')));
    expect(rated, 1);
    expect(tester.takeException(), isNull);
  });
}

GuidePersonView _guest() {
  return const GuidePersonView(
    account: null,
    allowance: GuideAllowance.guest(),
    languageName: 'English',
    appearance: GuideAppearance.system,
    showFieldGuide: true,
    showOffline: false,
    offlineOn: false,
  );
}

GuidePersonView _month() {
  return GuidePersonView(
    account: const GuidePersonAccount(
      name: 'Anna Novák',
      email: 'anna.novak@gmail.com',
      provider: GuideAccountProvider.google,
    ),
    allowance: GuideAllowance.month(
      used: 2,
      fromAds: 1,
      now: DateTime(2026, 9, 30),
    ),
    languageName: 'English',
    appearance: GuideAppearance.system,
    showFieldGuide: true,
    showOffline: true,
    offlineOn: true,
  );
}

GuidePersonView _fieldGuide() {
  return const GuidePersonView(
    account: GuidePersonAccount(
      name: 'Anna Novák',
      email: 'anna.novak@gmail.com',
      provider: GuideAccountProvider.google,
    ),
    allowance: GuideAllowance.unlimited(
      fieldGuide: true,
      unlimitedNames: true,
      noAds: true,
      seenSynced: true,
    ),
    languageName: 'English',
    appearance: GuideAppearance.system,
    showFieldGuide: true,
    showOffline: false,
    offlineOn: false,
  );
}

Widget _page({
  required GuidePersonView view,
  Future<void> Function(BuildContext context)? onSignIn,
  Future<void> Function(BuildContext context)? onSignOut,
  Future<void> Function(BuildContext context)? onDeleteAccount,
  Future<void> Function(BuildContext context)? onRestore,
  Future<void> Function(BuildContext context)? onLanguage,
  Future<void> Function(BuildContext context)? onFieldGuide,
  ValueChanged<GuideAppearance>? onAppearance,
  ValueChanged<int>? onSelectTab,
  Future<void> Function(String line)? onCopyVersion,
  Future<void> Function()? onRate,
}) {
  return GuidePersonPage(
    view: view,
    onSignIn: onSignIn,
    onSignOut: onSignOut,
    onDeleteAccount: onDeleteAccount,
    onRestore: onRestore,
    onLanguage: onLanguage,
    onFieldGuide: onFieldGuide,
    onAppearance: onAppearance,
    onSelectTab: onSelectTab,
    onCopyVersion: onCopyVersion,
    onRate: onRate,
    versionName: '9.0.0',
    buildNumber: '900',
  );
}

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    home: home,
  );
}
