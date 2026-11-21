import 'package:flutter/widgets.dart';

/// Families opens first. All lists on Find switches to [lists].
enum GuideBookSegment { families, genera, lists }

const guideHabitatRouteName = 'GuideHabitat';
const guidePetalRouteName = 'GuidePetal';
const guideConeRouteName = 'GuideCone';
const guideResultsRouteName = 'GuideResults';
const guideListRouteName = 'GuideList';
const guideSpeciesRouteName = 'GuideSpecies';
const guidePersonRouteName = 'GuidePerson';
const guideLanguageRouteName = 'GuideLanguage';
const guideFieldGuideRouteName = 'GuideFieldGuide';
const guideOfflineRouteName = 'GuideOffline';
const guideStatsRouteName = 'GuideStats';
const guideSearchRouteName = 'GuideSearch';
const guideCameraRouteName = 'GuideCamera';
const guideOutsideRouteName = 'GuideOutside';
const guideCustomRouteName = 'GuideCustom';

/// Tab actions for the field-guide shell. A pushed page cannot see the
/// shell's inherited widgets, so it calls these.
class GuideTabs {
  /// The shell tab under any pushed page. The landscape rail reads it.
  static int index = 0;
  static void Function(int index)? show;
  static VoidCallback? showSeen;
  static VoidCallback? refreshSeen;

  /// Opens Person. The shell sets this; a rail on a pushed page calls it.
  static void Function(BuildContext context)? openPerson;

  /// Unconfirmed finds waiting on Seen. The shell writes this. Every bottom
  /// bar reads it, including bars on pages pushed over the shell.
  static final ValueNotifier<int> unconfirmed = ValueNotifier(0);
}

/// Leaves the key, or a custom list, and opens a shell tab. Find stays
/// selected while the key is open; tapping Find, Book, or Seen returns to
/// that tab.
void leaveGuideKeyForTab(BuildContext context, int index) {
  GuideTabs.show?.call(index);
  Navigator.popUntil(context, (route) {
    final name = route.settings.name;
    return name != guideCustomRouteName && !guideIsKeyRoute(name);
  });
}

/// Opens a shell tab and drops every page pushed over it.
void guideRailSelect(BuildContext context, int index) {
  GuideTabs.show?.call(index);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Person in the landscape rail. A page already on Person stays there.
void guideRailPerson(BuildContext context) {
  final navigator = Navigator.of(context);
  if (ModalRoute.of(context)?.settings.name == guidePersonRouteName) return;
  var found = false;
  navigator.popUntil((route) {
    if (route.settings.name == guidePersonRouteName) found = true;
    return route.isFirst || found;
  });
  if (!found) GuideTabs.openPerson?.call(navigator.context);
}

bool guideIsKeyRoute(String? name) {
  return name == guideHabitatRouteName ||
      name == guidePetalRouteName ||
      name == guideConeRouteName ||
      name == guideResultsRouteName;
}

void popGuideKeyToFind(BuildContext context) {
  Navigator.popUntil(context, (route) => !guideIsKeyRoute(route.settings.name));
}

/// The key on the camera returns to Find, including when search or the key
/// is still underneath.
void leaveGuideCameraForFind(BuildContext context) {
  GuideTabs.show?.call(0);
  Navigator.popUntil(context, (route) {
    final name = route.settings.name;
    return name != guideCameraRouteName &&
        name != guideOutsideRouteName &&
        name != guideSearchRouteName &&
        !guideIsKeyRoute(name);
  });
}

void popGuideKeyToHabitat(BuildContext context) {
  Navigator.popUntil(context, (route) {
    final name = route.settings.name;
    return name != guidePetalRouteName &&
        name != guideConeRouteName &&
        name != guideResultsRouteName;
  });
}
