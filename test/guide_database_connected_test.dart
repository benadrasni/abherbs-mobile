import 'dart:async';

import 'package:abherbs_flutter/data/guide_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetGuideDatabaseConnectionForTest);

  test('an open socket lets the plant read start', () async {
    var offline = 0;
    guideDatabaseGoOfflineForTest = () async {
      offline++;
    };
    guideDatabaseConnectionForTest = () => Stream<bool>.value(true);
    await guideDatabaseConnected(wait: const Duration(seconds: 2));
    expect(offline, 0);
  });

  test('a down socket is closed and opened before the plant read', () async {
    final order = <String>[];
    var listens = 0;
    guideDatabaseGoOfflineForTest = () async {
      order.add('offline');
    };
    guideDatabaseGoOnlineForTest = () async {
      order.add('online');
    };
    guideDatabaseConnectionForTest = () {
      listens++;
      if (listens == 1) return Stream<bool>.value(false);
      return Stream<bool>.fromIterable(const [false, true]);
    };
    await guideDatabaseConnected(wait: const Duration(seconds: 2));
    expect(order, ['offline', 'online']);
    expect(listens, 2);
  });

  test('a background plant notice replaces a socket that still says up',
      () async {
    final order = <String>[];
    final socket = StreamController<bool>();
    addTearDown(socket.close);
    socket.add(true);
    guideDatabaseConnectionForTest = () => socket.stream;
    guideDatabaseGoOfflineForTest = () async {
      order.add('offline');
      socket.add(false);
    };
    guideDatabaseGoOnlineForTest = () async {
      order.add('online');
      socket.add(true);
    };
    guideDatabaseReconnectOnNextRead();
    await guideDatabaseConnected(wait: const Duration(seconds: 2));
    expect(order, ['offline', 'online']);
  });

  test('a second read joins the reconnect already running', () async {
    var offline = 0;
    final socket = StreamController<bool>();
    addTearDown(socket.close);
    socket.add(true);
    final offlineGate = Completer<void>();
    guideDatabaseConnectionForTest = () => socket.stream;
    guideDatabaseGoOfflineForTest = () {
      offline++;
      socket.add(false);
      return offlineGate.future;
    };
    guideDatabaseGoOnlineForTest = () async {
      socket.add(true);
    };
    guideDatabaseReconnectOnNextRead();
    final first = guideDatabaseConnected(wait: const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    final second = guideDatabaseConnected(wait: const Duration(seconds: 2));
    offlineGate.complete();
    await Future.wait([first, second]);
    expect(offline, 1);
  });

  test('a socket that stays down still lets the plant read start', () async {
    guideDatabaseGoOfflineForTest = () async {};
    guideDatabaseGoOnlineForTest = () async {};
    guideDatabaseConnectionForTest = () => Stream<bool>.multi((controller) {
          controller.add(false);
        });
    final started = Stopwatch()..start();
    await guideDatabaseConnected(wait: const Duration(milliseconds: 80));
    expect(
      started.elapsed,
      greaterThan(const Duration(milliseconds: 40)),
    );
    expect(started.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('goOffline failing still opens the socket', () async {
    final order = <String>[];
    var listens = 0;
    guideDatabaseGoOfflineForTest = () async {
      order.add('offline');
      throw StateError('channel');
    };
    guideDatabaseGoOnlineForTest = () async {
      order.add('online');
    };
    guideDatabaseConnectionForTest = () {
      listens++;
      if (listens == 1) return Stream<bool>.value(false);
      return Stream<bool>.fromIterable(const [false, true]);
    };
    await guideDatabaseConnected(wait: const Duration(seconds: 2));
    expect(order, ['offline', 'online']);
  });
}
