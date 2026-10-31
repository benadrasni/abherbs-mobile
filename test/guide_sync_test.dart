import 'dart:async';

import 'package:abherbs_flutter/data/guide_sync.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSnapshot extends Fake implements DataSnapshot {
  _FakeSnapshot(this.value);

  @override
  final Object? value;
}

class _FakeQuery extends Fake implements Query {
  _FakeQuery(this.path);

  @override
  final String path;

  int gets = 0;
  int orderByKeyGets = 0;
  int onceCalls = 0;

  @override
  Future<DataSnapshot> get() async {
    gets++;
    return _FakeSnapshot('get:$path');
  }

  @override
  Query orderByKey() => _FakeOrderByKeyQuery(this);

  @override
  Future<DatabaseEvent> once([
    DatabaseEventType eventType = DatabaseEventType.value,
  ]) {
    onceCalls++;
    throw UnimplementedError('once() should not be called');
  }
}

class _FakeOrderByKeyQuery extends Fake implements Query {
  _FakeOrderByKeyQuery(this._parent);

  final _FakeQuery _parent;

  @override
  String get path => _parent.path;

  @override
  Future<DataSnapshot> get() async {
    _parent.orderByKeyGets++;
    return _FakeSnapshot('orderByKey.get:${_parent.path}');
  }
}

class _FakeDatabaseReference extends _FakeQuery implements DatabaseReference {
  _FakeDatabaseReference(
    super.path, {
    Future<void> Function(bool value)? onKeepSynced,
  }) : _onKeepSynced = onKeepSynced;

  final Future<void> Function(bool value)? _onKeepSynced;
  final List<bool> syncedValues = [];

  @override
  Future<void> keepSynced(bool value) {
    syncedValues.add(value);
    if (_onKeepSynced != null) return _onKeepSynced(value);
    return Future.value();
  }
}

void main() {
  const headers = 'plants_headers_v3';

  setUp(resetGuideSyncForTest);

  test('a kept path is tracked and its child is not', () {
    final generation = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, generation, applied: true);

    expect(guidePathKeptSynced(headers), isTrue);
    expect(guidePathKeptSynced('/$headers'), isTrue);
    expect(guidePathKeptSynced('$headers/12'), isFalse);

    final release = guideSyncBegin('/$headers', false);
    guideSyncFinish(headers, false, release, applied: true);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test('an older keep does not undo a newer release', () {
    final older = guideSyncBegin(headers, true);
    final newer = guideSyncBegin(headers, false);
    guideSyncFinish(headers, true, older, applied: true);
    expect(guidePathKeptSynced(headers), isTrue);

    guideSyncFinish(headers, false, newer, applied: true);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test('a late older keep does not put a released path back', () {
    final older = guideSyncBegin(headers, true);
    final newer = guideSyncBegin(headers, false);
    guideSyncFinish(headers, false, newer, applied: true);
    guideSyncFinish(headers, true, older, applied: true);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test('an older release does not undo a newer keep', () {
    final older = guideSyncBegin(headers, false);
    final newer = guideSyncBegin(headers, true);
    guideSyncFinish(headers, false, older, applied: true);
    guideSyncFinish(headers, true, newer, applied: true);
    expect(guidePathKeptSynced(headers), isTrue);
  });

  test('a failed keep drops the mark and a failed release leaves it', () {
    final failed = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, failed, applied: false);
    expect(guidePathKeptSynced(headers), isFalse);

    final kept = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, kept, applied: true);
    final release = guideSyncBegin(headers, false);
    guideSyncFinish(headers, false, release, applied: false);
    expect(guidePathKeptSynced(headers), isTrue);
  });

  test('a newer failed keep or release does not undo an older one that worked',
      () {
    // Older keep succeeds, newer overlapping keep fails.
    final keep1 = guideSyncBegin(headers, true);
    final keep2 = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, keep2, applied: false);
    expect(guidePathKeptSynced(headers), isTrue);
    guideSyncFinish(headers, true, keep1, applied: true);
    expect(guidePathKeptSynced(headers), isTrue);

    // Another keep after it is already synced fails.
    final keep3 = guideSyncBegin(headers, true);
    guideSyncFinish(headers, true, keep3, applied: false);
    expect(guidePathKeptSynced(headers), isTrue);

    // Older release succeeds, newer overlapping release fails.
    final release1 = guideSyncBegin(headers, false);
    final release2 = guideSyncBegin(headers, false);
    guideSyncFinish(headers, false, release1, applied: true);
    guideSyncFinish(headers, false, release2, applied: false);
    expect(guidePathKeptSynced(headers), isFalse);

    // Failed keep and failed release on an unsynced path leave it unsynced.
    final keep4 = guideSyncBegin(headers, true);
    final release3 = guideSyncBegin(headers, false);
    guideSyncFinish(headers, true, keep4, applied: false);
    expect(guidePathKeptSynced(headers), isFalse);
    guideSyncFinish(headers, false, release3, applied: false);
    expect(guidePathKeptSynced(headers), isFalse);
  });

  test(
      'guideServerGet uses orderByKey().get() while kept or in flight and get() otherwise',
      () async {
    final keepGate = Completer<void>();
    final releaseGate = Completer<void>();
    final ref = _FakeDatabaseReference(
      headers,
      onKeepSynced: (value) => value ? keepGate.future : releaseGate.future,
    );
    final childRef = _FakeDatabaseReference('$headers/12');
    final queryAtSamePath = _FakeQuery(headers);

    // Before keepSynced: plain get().
    expect((await guideServerGet(ref)).value, 'get:$headers');
    expect(ref.gets, 1);
    expect(ref.orderByKeyGets, 0);
    expect(ref.onceCalls, 0);

    // While keepSynced(true) is in flight: orderByKey().get(), never once().
    final keepFuture = guideKeepSynced(ref, true);
    expect(guidePathKeptSynced(headers), isTrue);
    expect((await guideServerGet(ref)).value, 'orderByKey.get:$headers');
    expect(ref.gets, 1);
    expect(ref.orderByKeyGets, 1);
    expect(ref.onceCalls, 0);

    // Child DatabaseReference and non-DatabaseReference Query still use get().
    expect((await guideServerGet(childRef)).value, 'get:$headers/12');
    expect(childRef.gets, 1);
    expect(childRef.orderByKeyGets, 0);
    expect((await guideServerGet(queryAtSamePath)).value, 'get:$headers');
    expect(queryAtSamePath.gets, 1);
    expect(queryAtSamePath.orderByKeyGets, 0);

    // After keepSynced(true) finishes: still orderByKey().get().
    keepGate.complete();
    await keepFuture;
    expect(guidePathKeptSynced(headers), isTrue);
    expect((await guideServerGet(ref)).value, 'orderByKey.get:$headers');
    expect(ref.orderByKeyGets, 2);

    // While keepSynced(false) is in flight: still orderByKey().get().
    final releaseFuture = guideKeepSynced(ref, false);
    expect(guidePathKeptSynced(headers), isTrue);
    expect((await guideServerGet(ref)).value, 'orderByKey.get:$headers');
    expect(ref.orderByKeyGets, 3);

    // After keepSynced(false) finishes: back to plain get().
    releaseGate.complete();
    await releaseFuture;
    expect(guidePathKeptSynced(headers), isFalse);
    expect((await guideServerGet(ref)).value, 'get:$headers');
    expect(ref.gets, 2);
    expect(ref.orderByKeyGets, 3);
    expect(ref.onceCalls, 0);
    expect(ref.syncedValues, [true, false]);
  });

  test('guideKeepSynced preserves a working keep or release when another fails',
      () async {
    var call = 0;
    final ref = _FakeDatabaseReference(
      headers,
      onKeepSynced: (_) async {
        call++;
        if (call == 2 || call == 4) {
          throw StateError('channel failed');
        }
      },
    );

    // First keep succeeds, second overlapping keep throws.
    await Future.wait([
      guideKeepSynced(ref, true),
      expectLater(guideKeepSynced(ref, true), throwsStateError),
    ]);
    expect(guidePathKeptSynced(headers), isTrue);
    expect((await guideServerGet(ref)).value, 'orderByKey.get:$headers');

    // First release succeeds, second overlapping release throws.
    await Future.wait([
      guideKeepSynced(ref, false),
      expectLater(guideKeepSynced(ref, false), throwsStateError),
    ]);
    expect(guidePathKeptSynced(headers), isFalse);
    expect((await guideServerGet(ref)).value, 'get:$headers');
  });
}
