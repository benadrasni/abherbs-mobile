import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Locations this process has asked the SDK to keep synced.
///
/// Android Realtime Database 22.0.2 asserts when [Query.get] runs on a query
/// that is already `keepSynced`. That `get` turns the sync off without
/// dropping the connection listen, and the next listener calls `listen`
/// again for the same query (firebase-android-sdk #8433). The SDK fix is
/// not in 22.0.2 or 23.0.0. [Query.once] listens beside the existing sync
/// and does not take that path.
///
/// A child of a kept path is a different query, and so is any `orderBy` or
/// `limit` query. Those stay on [Query.get], which still bypasses a stale
/// disk copy. The latest request wins: a newer `keepSynced(true)` is not
/// cleared by an older `keepSynced(false)` that finishes afterwards.
final Map<String, int> _generation = {};
final Set<String> _synced = {};

String _guideDatabasePath(String path) {
  if (path.startsWith('/')) return path.substring(1);
  return path;
}

/// Marks [path] before the native call. A read that arrives while
/// `keepSynced(true)` is still queued then uses [Query.once].
@visibleForTesting
int guideSyncBegin(String path, bool value) {
  final key = _guideDatabasePath(path);
  final generation = (_generation[key] ?? 0) + 1;
  _generation[key] = generation;
  if (value) _synced.add(key);
  return generation;
}

/// Applies the outcome of generation [generation] only when it is still the
/// latest request. A failed `keepSynced(true)` drops the mark. A failed
/// `keepSynced(false)` leaves it, because the listen may still be up.
@visibleForTesting
void guideSyncFinish(
  String path,
  bool value,
  int generation, {
  required bool applied,
}) {
  final key = _guideDatabasePath(path);
  if (_generation[key] != generation) return;
  if (!value) {
    if (applied) _synced.remove(key);
    return;
  }
  if (!applied) _synced.remove(key);
}

@visibleForTesting
bool guidePathKeptSynced(String path) =>
    _synced.contains(_guideDatabasePath(path));

@visibleForTesting
void resetGuideSyncForTest() {
  _generation.clear();
  _synced.clear();
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
/// [guideKeepSynced]. [Query.once] when it is.
Future<DataSnapshot> guideServerGet(Query query) {
  if (query is DatabaseReference && guidePathKeptSynced(query.path)) {
    return query.once().then((event) => event.snapshot);
  }
  return query.get();
}
