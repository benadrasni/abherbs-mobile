import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Locations this process has asked the SDK to keep synced.
///
/// Android Realtime Database 22.0.2 asserts when [Query.get] runs on a
/// [DatabaseReference] that is already `keepSynced`. That `get` turns the
/// default query's sync off without dropping the connection listen, and the
/// next listener calls `listen` again for the same query
/// (firebase-android-sdk #8433). The SDK fix is not in 22.0.2 or 23.0.0.
///
/// [Query.orderByKey] at that path has a different `QuerySpec` than the
/// default query `keepSynced` registers, and it is not `isDefault()`, so its
/// [Query.get] fetches from the server without removing the `keepSynced` view
/// or reading a stale on-disk copy while `keepSynced` is starting or stopping.
///
/// A child of a kept path is a different query, and so is any `orderBy` or
/// `limit` query. Those stay on [Query.get]. The latest request wins: a newer
/// `keepSynced(true)` is not cleared by an older `keepSynced(false)` that
/// finishes afterwards.
class _PathSync {
  int generation = 0;
  int appliedGeneration = 0;
  bool appliedSynced = false;
  final Set<int> pendingKeeps = {};

  bool get isSynced => appliedSynced || pendingKeeps.isNotEmpty;
}

final Map<String, _PathSync> _paths = {};

String _guideDatabasePath(String path) {
  if (path.startsWith('/')) return path.substring(1);
  return path;
}

/// Marks [path] before the native call. A read that arrives while
/// `keepSynced(true)` is still queued then uses [Query.orderByKey].
@visibleForTesting
int guideSyncBegin(String path, bool value) {
  final key = _guideDatabasePath(path);
  final state = _paths.putIfAbsent(key, _PathSync.new);
  final generation = ++state.generation;
  if (value) state.pendingKeeps.add(generation);
  return generation;
}

/// Records the outcome of generation [generation]. Only a call that reached
/// the native SDK ([applied]) advances the applied state, so a newer call
/// that fails does not undo an older keep or release that succeeded.
@visibleForTesting
void guideSyncFinish(
  String path,
  bool value,
  int generation, {
  required bool applied,
}) {
  final state = _paths[_guideDatabasePath(path)];
  if (state == null) return;
  state.pendingKeeps.remove(generation);
  if (applied && generation > state.appliedGeneration) {
    state.appliedGeneration = generation;
    state.appliedSynced = value;
  }
}

@visibleForTesting
bool guidePathKeptSynced(String path) =>
    _paths[_guideDatabasePath(path)]?.isSynced ?? false;

@visibleForTesting
void resetGuideSyncForTest() {
  _paths.clear();
}

Future<void> guideKeepSynced(DatabaseReference ref, bool value) async {
  final generation = guideSyncBegin(ref.path, value);
  var applied = false;
  try {
    await ref.keepSynced(value);
    applied = true;
  } finally {
    guideSyncFinish(ref.path, value, generation, applied: applied);
  }
}

/// [Query.get] when [query] is not the exact location passed to
/// [guideKeepSynced]. `query.orderByKey().get()` when it is.
Future<DataSnapshot> guideServerGet(Query query) {
  if (query is DatabaseReference && guidePathKeptSynced(query.path)) {
    return query.orderByKey().get();
  }
  return query.get();
}
