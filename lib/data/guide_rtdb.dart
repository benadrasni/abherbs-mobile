import 'dart:async';

import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// How long a key index may take before the copy already on the phone is used.
/// `.once()` on a node that was never downloaded does not finish in flight mode.
/// Dead wi-fi still reports an interface, so the same limit applies there.
const guideIndexWait = Duration(seconds: 4);

/// How long a resumed process may wait for a new Realtime Database socket.
/// A get started on a dead socket keeps running after Dart times out.
const _guideConnectWait = Duration(seconds: 8);

/// True when the phone reports no network. A check that throws counts as
/// online, so a working connection still reads the indexes.
Future<bool> guideOnPhoneOnly() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.every((item) => item == ConnectivityResult.none);
  } catch (error) {
    debugPrint('guide connectivity: $error');
    return false;
  }
}

/// A server read, or the pack already on the phone.
///
/// [fromPhone] is set when that pack was used. The pack is a stored list, a
/// language entry, or key-plant headers, not another get of the node that waited.
Future<({T value, bool fromPhone})> guideReadOrPack<T>(
  Future<T> Function() online,
  Future<T> Function() pack, {
  bool? phoneOnly,
  Duration wait = guideIndexWait,
  String label = 'guide read',
}) async {
  if (!(phoneOnly ?? await guideOnPhoneOnly())) {
    try {
      return (value: await online().timeout(wait), fromPhone: false);
    } catch (error) {
      debugPrint('$label: $error');
    }
  }
  return (value: await pack(), fromPhone: true);
}

/// Local copy when [phoneOnly]. Otherwise one `.once()`, then the caller's pack.
Future<dynamic> guideChildValue(
  DatabaseReference ref, {
  required bool phoneOnly,
}) async {
  if (phoneOnly) {
    final snapshot = await guideServerGet(ref).timeout(guideIndexWait);
    return snapshot.value;
  }
  final event = await ref.once().timeout(guideIndexWait);
  return event.snapshot.value;
}

/// One step of `.info/connected` while a socket is being replaced.
enum _GuideSocket { down, up, quiet }

/// Set by a background plant notification. The SDK can still report the
/// socket as up after the process was frozen.
bool _guideForceReconnect = false;

Future<void>? _guideReconnect;

@visibleForTesting
Future<void> Function()? guideDatabaseGoOfflineForTest;

@visibleForTesting
Future<void> Function()? guideDatabaseGoOnlineForTest;

@visibleForTesting
Stream<bool> Function()? guideDatabaseConnectionForTest;

@visibleForTesting
void resetGuideDatabaseConnectionForTest() {
  _guideForceReconnect = false;
  _guideReconnect = null;
  guideDatabaseGoOfflineForTest = null;
  guideDatabaseGoOnlineForTest = null;
  guideDatabaseConnectionForTest = null;
}

/// The next online species read opens a new socket before it reads.
void guideDatabaseReconnectOnNextRead() {
  _guideForceReconnect = true;
}

/// Clears a pending reconnect when the phone has no network interface.
void clearGuideDatabasePendingReconnect() {
  _guideForceReconnect = false;
}

Stream<bool> _guideConnection() {
  final override = guideDatabaseConnectionForTest;
  if (override != null) return override();
  return FirebaseDatabase.instance.ref('.info/connected').onValue.map(
        (event) => event.snapshot.value == true,
      );
}

Future<void> _guideGoOffline() {
  final override = guideDatabaseGoOfflineForTest;
  if (override != null) return override();
  return FirebaseDatabase.instance.goOffline();
}

Future<void> _guideGoOnline() {
  final override = guideDatabaseGoOnlineForTest;
  if (override != null) return override();
  return FirebaseDatabase.instance.goOnline();
}

Future<_GuideSocket> _guidePullSocket(
  StreamIterator<bool> events,
  Duration wait,
) async {
  if (wait <= Duration.zero) return _GuideSocket.quiet;
  try {
    final moved = await events.moveNext().timeout(wait);
    if (!moved) return _GuideSocket.quiet;
    return events.current ? _GuideSocket.up : _GuideSocket.down;
  } on TimeoutException {
    return _GuideSocket.quiet;
  }
}

/// Closes the socket and opens another. [goOnline] alone does nothing unless
/// [goOffline] ran: the SDK only resumes an interrupt it recorded.
Future<void> _guideDatabaseReconnectBody({
  Duration wait = _guideConnectWait,
}) async {
  debugPrint('guide database: reconnect');
  final events = StreamIterator<bool>(_guideConnection());
  try {
    var sawDown = await _guidePullSocket(events, wait) == _GuideSocket.down;
    try {
      await _guideGoOffline().timeout(wait);
    } catch (error) {
      debugPrint('guide database offline: $error');
    }
    final down = Stopwatch()..start();
    while (!sawDown && down.elapsed < wait) {
      final pull = await _guidePullSocket(events, wait - down.elapsed);
      if (pull == _GuideSocket.quiet) break;
      sawDown = pull == _GuideSocket.down;
    }
    try {
      await _guideGoOnline().timeout(wait);
    } catch (error) {
      debugPrint('guide database online: $error');
    }
    final up = Stopwatch()..start();
    var connected = false;
    while (!connected && up.elapsed < wait) {
      final pull = await _guidePullSocket(events, wait - up.elapsed);
      if (pull == _GuideSocket.quiet) break;
      connected = pull == _GuideSocket.up;
    }
    if (!connected) debugPrint('guide database connected: still down');
  } catch (error) {
    debugPrint('guide database connected: $error');
  } finally {
    await events.cancel();
  }
}

@visibleForTesting
Future<void> guideDatabaseReconnect({Duration wait = _guideConnectWait}) {
  final existing = _guideReconnect;
  if (existing != null) return existing;
  late final Future<void> run;
  run = _guideDatabaseReconnectBody(wait: wait).whenComplete(() {
    if (identical(_guideReconnect, run)) _guideReconnect = null;
  });
  _guideReconnect = run;
  return run;
}

/// Waits until the socket is up, opening a new one when it is down or when
/// [guideDatabaseReconnectOnNextRead] asked for one.
Future<void> guideDatabaseConnected({Duration wait = _guideConnectWait}) async {
  final pending = _guideReconnect;
  if (pending != null) {
    try {
      await pending;
    } catch (error) {
      debugPrint('guide database connected: $error');
    }
    return;
  }
  if (_guideForceReconnect) {
    _guideForceReconnect = false;
  } else {
    try {
      final events = StreamIterator<bool>(_guideConnection());
      try {
        if (await _guidePullSocket(events, wait) == _GuideSocket.up) return;
      } finally {
        await events.cancel();
      }
    } catch (error) {
      debugPrint('guide database connected: $error');
    }
  }
  try {
    await guideDatabaseReconnect(wait: wait);
  } catch (error) {
    debugPrint('guide database connected: $error');
  }
}
