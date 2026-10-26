import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../religious_activity/data/activity_store.dart';

const restoreJournalKey = 'haq.restore.journal.v1';

Future<void> writeBackupPreference(
  SharedPreferences prefs,
  String key,
  Object? value,
) async {
  final saved = value == null
      ? await prefs.remove(key)
      : value is bool
      ? await prefs.setBool(key, value)
      : await prefs.setString(key, value as String);
  if (!saved) throw StateError('Preference write failed');
}

/// Runs before any Quran/account/settings state is loaded. A crash before the
/// SQLite commit restores the previous preferences; after commit it keeps them.
Future<void> recoverHaqRestore(
  SharedPreferences prefs, {
  ReligiousActivityStore? store,
}) async {
  final raw = prefs.getString(restoreJournalKey);
  if (raw == null) return;
  final journal = jsonDecode(raw) as Map;
  final database = store ?? await ReligiousActivityStore.open();
  try {
    if (!await database.restoreCommitted(
      journal['scope'] as String,
      journal['id'] as String,
    )) {
      for (final entry in (journal['before'] as Map).entries) {
        await writeBackupPreference(prefs, entry.key as String, entry.value);
      }
    }
    await writeBackupPreference(prefs, restoreJournalKey, null);
  } finally {
    if (store == null) await database.close();
  }
}
