import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../quran/data/quran_sync.dart';
import '../../quran/data/quran_repository.dart';
import '../../quran/data/quran_controller.dart';
import '../../sakinah/data/breathing_session.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import '../../religious_content/data/religious_controller.dart';
import '../../settings/data/app_settings.dart';
import '../../prayer/data/prayer_models.dart';
import 'restore_journal.dart';

Object? _ordered(Object? value) => value is Map
    ? {
        for (final key in value.keys.cast<String>().toList()..sort())
          key: _ordered(value[key]),
      }
    : value is List
    ? value.map(_ordered).toList()
    : value;
String _canonical(Object? value) => jsonEncode(_ordered(value));

/// An integrity checksum detects corruption, not the identity of the author.
/// Every decoded field is validated independently before the first local write.
class HaqBackupArchive {
  HaqBackupArchive._(this.document);
  final Map<String, dynamic> document;
  static const maxBytes = 8 * 1024 * 1024;
  String get scope => document['scope'] as String;
  Map<String, dynamic> get payload =>
      Map<String, dynamic>.from(document['payload'] as Map);
  DateTime get created => DateTime.parse(document['created'] as String);
  Map<String, dynamic> get personal =>
      Map<String, dynamic>.from(payload['personal'] as Map);
  List<ReligiousActivityEvent> get events => (payload['events'] as List)
      .map(
        (e) => ReligiousActivityEvent.fromJson(
          Map<String, dynamic>.from(e as Map),
        ),
      )
      .toList();
  factory HaqBackupArchive.create(String scope, Map<String, dynamic> payload) =>
      HaqBackupArchive._({
        'format': 'haq.backup',
        'schema': 1,
        'scope': scope,
        'created': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      });
  String encode() {
    final text = _canonical({
      ...document,
      'sha256': sha256.convert(utf8.encode(_canonical(document))).toString(),
    });
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('النسخة تتجاوز 8 ميغابايت');
    }
    return text;
  }

  factory HaqBackupArchive.decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('الملف أكبر من الحد المسموح');
    }
    try {
      final data = Map<String, dynamic>.from(jsonDecode(text) as Map);
      final checksum = data.remove('sha256');
      if (data.length != 5 ||
          data['format'] != 'haq.backup' ||
          data['schema'] != 1 ||
          checksum !=
              sha256.convert(utf8.encode(_canonical(data))).toString()) {
        throw const FormatException();
      }
      final archive = HaqBackupArchive._(data);
      if (archive.scope != 'guest' &&
          !RegExp(r'^account\.[1-9][0-9]*$').hasMatch(archive.scope)) {
        throw const FormatException();
      }
      archive.created;
      final payload = archive.payload;
      if (payload.length != 5 ||
          !payload.keys.toSet().containsAll({
            'quran',
            'content',
            'personal',
            'events',
            'settings',
          })) {
        throw const FormatException();
      }
      for (final e in archive.personal.entries) {
        final parts = e.key.split(':');
        if (parts.length != 2) throw const FormatException();
        final entity = PersonalEntity.fromJson(
          PersonalEntityKind.values.byName(parts[0]),
          Map<String, dynamic>.from(e.value as Map),
        );
        if (entity.key != e.key ||
            _canonical(entity.toJson()) != _canonical(e.value)) {
          throw const FormatException();
        }
      }
      if ((payload['events'] as List).length > 50000 ||
          archive.personal.length > 10000) {
        throw const FormatException();
      }
      final ids = <String>{};
      final events = archive.events;
      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        if (!ids.add(event.id)) throw const FormatException();
        if (_canonical(event.toJson()) !=
            _canonical((payload['events'] as List)[i])) {
          throw const FormatException();
        }
      }
      return archive;
    } catch (_) {
      throw const FormatException(
        'النسخة تالفة أو إصدارها غير مدعوم. لم تتغيّر بياناتك.',
      );
    }
  }
}

class HaqBackup {
  HaqBackup(this.activity, this.content, {this.writePreference});
  final ReligiousActivityController activity;
  final ReligiousController content;
  final Future<void> Function(String key, Object? value)? writePreference;
  bool busy = false;
  QuranController get quran => activity.quran;

  static Map<String, String> settingsKeys(String scope) => {
    'app': 'app.settings.v1.$scope',
    'prayer': 'prayer.config.v1.$scope',
    'adhkar': 'adhkar.display.v1.$scope',
    'sakinah': 'sakinah.settings.$scope',
    for (final name in ['haptic', 'auto', 'countSound', 'goalSound'])
      'tasbih.$name': 'tasbih.settings.v1.$scope.$name',
  };

  Future<void> _lock() async {
    if (busy || quran.account.busy || quran.account.maintenance) {
      throw StateError('العملية مشغولة');
    }
    busy = true;
    quran.account.maintenance = content.maintenance = activity.maintenance =
        true;
    try {
      await quran.flushReading();
      await Future.wait<void>([
        quran.account.settle(),
        content.settle(),
        activity.syncClient.settle(),
      ]);
    } catch (_) {
      _unlock();
      rethrow;
    }
  }

  void _unlock() {
    quran.account.maintenance = content.maintenance = activity.maintenance =
        false;
    busy = false;
  }

  Future<HaqBackupArchive> capture() async {
    var locked = false;
    try {
      await _lock();
      locked = true;
      final scope = activity.scope;
      final entities = await activity.store.entities(scope);
      final history = await activity.store.events(scope);
      final archive = HaqBackupArchive.create(scope, {
        'quran': quran.account.entities(),
        'content': content.entities,
        'personal': {for (final e in entities) e.key: e.toJson()},
        'events': history.map((e) => e.toJson()).toList(),
        'settings': {
          for (final e in settingsKeys(scope).entries)
            if (quran.preferences!.containsKey(e.value))
              e.key: quran.preferences!.get(e.value),
        },
      });
      validate(archive);
      return archive;
    } finally {
      if (locked) _unlock();
    }
  }

  void validate(HaqBackupArchive archive) {
    if (archive.scope != activity.scope) {
      throw const FormatException(
        'النسخة تخص ضيفًا أو حسابًا آخر. افتح نفس الحساب أولًا.',
      );
    }
    final payload = archive.payload;
    final values = Map<String, dynamic>.from(payload['quran'] as Map);
    final repo = quran.repository as QuranRepository;
    for (final e in values.entries) {
      final key = e.key;
      if (key.startsWith('favorite:') || key.startsWith('bookmark:')) {
        final verse = key.substring(key.indexOf(':') + 1);
        if (!repo.byKey.containsKey(verse) ||
            e.value is! String ||
            DateTime.tryParse(e.value as String) == null) {
          throw const FormatException('علامة قرآن غير صالحة');
        }
      } else if (key.startsWith('surah:') || key.startsWith('juz:')) {
        final n = int.tryParse(key.split(':')[1]);
        if (n == null ||
            n < 1 ||
            n > (key.startsWith('surah:') ? 114 : 30) ||
            e.value != true) {
          throw const FormatException('فهرس قرآن غير صالح');
        }
      } else if (key == 'reading') {
        final v = e.value as Map;
        if (v.keys.any((k) => !{'lastKey', 'page', 'alignment'}.contains(k)) ||
            !repo.byKey.containsKey(v['lastKey']) ||
            v['page'] is! int ||
            (v['page'] as int) < 1 ||
            (v['page'] as int) > 604 ||
            v['alignment'] is! num ||
            (v['alignment'] as num) < 0 ||
            (v['alignment'] as num) > .9) {
          throw const FormatException('موضع قراءة غير صالح');
        }
      } else if (key == 'preferences') {
        final v = e.value as Map;
        if (v.length != 3 ||
            !['continuous', 'ayah', 'pages'].contains(v['mode']) ||
            !['light', 'ivory', 'green', 'dark'].contains(v['paper']) ||
            v['fontSize'] is! num ||
            (v['fontSize'] as num) < 18 ||
            (v['fontSize'] as num) > 36) {
          throw const FormatException('إعدادات قرآن غير صالحة');
        }
      } else {
        throw const FormatException('عنصر قرآن غير معروف');
      }
    }
    for (final e in (payload['content'] as Map).entries) {
      final key = e.key as String, at = (e.key as String).indexOf(':');
      if (at < 0 ||
          !{
            'favorite',
            'adhkar',
            'queue',
            'playback',
          }.contains(key.substring(0, at)) ||
          content.catalog?.byId.containsKey(key.substring(at + 1)) != true) {
        throw const FormatException('عنصر محتوى غير معروف');
      }
      if (key.startsWith('playback:')) {
        final v = e.value as Map;
        if (v.length != 2 ||
            v['seconds'] is! int ||
            v['index'] is! int ||
            (v['seconds'] as int) < 0 ||
            (v['index'] as int) < 0) {
          throw const FormatException('موضع صوت غير صالح');
        }
      } else if (e.value != true) {
        throw const FormatException('محفوظات غير صالحة');
      }
    }
    final settings = Map<String, dynamic>.from(payload['settings'] as Map);
    for (final e in settings.entries) {
      if (!settingsKeys(archive.scope).containsKey(e.key)) {
        throw const FormatException('إعداد غير معروف');
      }
      if (e.key.startsWith('tasbih.')) {
        if (e.value is! bool) {
          throw const FormatException('إعداد مسبحة غير صالح');
        }
        continue;
      }
      if (e.value is! String || (e.value as String).length > 64000) {
        throw const FormatException('إعداد غير صالح');
      }
      final v = Map<String, dynamic>.from(jsonDecode(e.value as String) as Map);
      if (e.key == 'app') {
        for (final setting in v.entries) {
          AppSettings.validate(
            setting.key,
            setting.key == 'content'
                ? List<String>.from(setting.value as List)
                : setting.value as Object,
          );
        }
      } else if (e.key == 'prayer') {
        PrayerConfig.fromJson(v);
        if (v.keys.any(
          (k) => !{
            'location',
            'method',
            'hanafi',
            'highLatitude',
            'adjustments',
            'notifications',
            'before',
            'after',
            'prayers',
          }.contains(k),
        )) {
          throw const FormatException('إعداد صلاة غير معروف');
        }
      } else {
        if (e.key == 'sakinah') {
          if (v.keys.any(
                (k) => !{
                  'pattern',
                  'minutes',
                  'custom',
                  'reduced',
                  'haptic',
                  'record',
                }.contains(k),
              ) ||
              v['pattern'] is! int ||
              (v['pattern'] as int) < 0 ||
              (v['pattern'] as int) > 3 ||
              ![1, 3, 5].contains(v['minutes']) ||
              v['reduced'] is! bool ||
              v['haptic'] is! bool ||
              v['record'] is! bool) {
            throw const FormatException('إعدادات سكينة غير صالحة');
          }
          final custom = List<int>.from(v['custom'] as List);
          if (custom.length != 4) {
            throw const FormatException('نمط تنفس غير صالح');
          }
          BreathingPattern(custom[0], custom[1], custom[2], custom[3]);
          continue;
        }
        final allowed = {
          'mode',
          'font',
          'size',
          'haptic_zero',
          'haptic_every',
          'hide_completed',
          'tap_text',
          'auto_advance',
          'dim',
          'volume_keys',
          'confirm_exit',
        };
        if (v.keys.any((k) => !allowed.contains(k))) {
          throw const FormatException('إعداد عرض غير معروف');
        }
        for (final setting in v.entries) {
          final valid = setting.key == 'mode'
              ? DhikrReadingMode.values.any((m) => m.name == setting.value)
              : setting.key == 'font'
              ? ['QuranUI', 'Tajawal', 'AmiriQuran'].contains(setting.value)
              : setting.key == 'size'
              ? setting.value is num &&
                    (setting.value as num) >= 16 &&
                    (setting.value as num) <= 42
              : setting.value is bool;
          if (!valid) throw const FormatException('إعداد عرض غير صالح');
        }
      }
    }
  }

  Future<void> restore(
    HaqBackupArchive archive, {
    required bool replace,
  }) async {
    archive = HaqBackupArchive.decode(archive.encode());
    validate(archive);
    final scope = activity.scope;
    final prefs = quran.preferences!;
    var journalWritten = false, committed = false, locked = false;
    try {
      await _lock();
      locked = true;
      if (activity.scope != scope) {
        throw StateError('تغير الحساب؛ أعد المحاولة');
      }
      final incoming = archive.payload;
      final qLedger = QuranSyncLedger(stored: quran.account.ledger.toJson());
      if (scope == 'guest') qLedger.record(quran.account.entities());
      final qValues = Map<String, dynamic>.from(incoming['quran'] as Map);
      if (replace) {
        qLedger.record(qValues);
      } else {
        qLedger.mergeGuest(qValues);
      }
      final cLedger = QuranSyncLedger(stored: content.ledger.toJson());
      if (scope == 'guest') cLedger.record(content.entities);
      final cValues = Map<String, dynamic>.from(incoming['content'] as Map);
      if (replace) {
        cLedger.record(cValues);
      } else {
        cLedger.mergeGuest(cValues);
      }
      final q = qLedger.visible, c = cLedger.visible;
      final updates = <String, Object?>{
        quran.account.stateKey: jsonEncode({
          ...?q['reading'] as Map?,
          ...?q['preferences'] as Map?,
          'favorites': {
            for (final e in q.entries)
              if (e.key.startsWith('favorite:')) e.key.substring(9): e.value,
          },
          'bookmarks': {
            for (final e in q.entries)
              if (e.key.startsWith('bookmark:')) e.key.substring(9): e.value,
          },
          'savedSurahs': [
            for (final k in q.keys)
              if (k.startsWith('surah:')) int.parse(k.substring(6)),
          ],
          'readJuzs': [
            for (final k in q.keys)
              if (k.startsWith('juz:')) int.parse(k.substring(4)),
          ],
        }),
        if (scope != 'guest')
          quran.account.ledgerKey: jsonEncode(qLedger.toJson()),
        'religious.sync.v1.$scope': jsonEncode(cLedger.toJson()),
        'religious.state.v1.$scope': jsonEncode({
          'favorites': [
            for (final k in c.keys)
              if (k.startsWith('favorite:')) k.substring(9),
          ],
          'customAdhkar': [
            for (final k in c.keys)
              if (k.startsWith('adhkar:')) k.substring(7),
          ],
          'queue': [
            for (final k in c.keys)
              if (k.startsWith('queue:')) k.substring(6),
          ],
          'progress': {
            for (final e in c.entries)
              if (e.key.startsWith('playback:')) e.key.substring(9): e.value,
          },
        }),
      };
      final settings = incoming['settings'] as Map;
      for (final e in settingsKeys(scope).entries) {
        if (replace || !prefs.containsKey(e.value)) {
          updates[e.value] = settings[e.key] as Object?;
        }
      }
      final before = {for (final key in updates.keys) key: prefs.get(key)};
      final id = operationId();
      await writeBackupPreference(
        prefs,
        restoreJournalKey,
        jsonEncode({'id': id, 'scope': scope, 'before': before}),
      );
      journalWritten = true;
      await activity.store.restoreBackup(
        scope,
        archive.personal,
        archive.events,
        replace: replace,
        restoreId: id,
        writePreferences: () async {
          for (final e in updates.entries) {
            await (writePreference?.call(e.key, e.value) ??
                writeBackupPreference(prefs, e.key, e.value));
          }
          if (activity.scope != scope) throw StateError('تغير الحساب');
        },
      );
      committed = true;
      try {
        await writeBackupPreference(prefs, restoreJournalKey, null);
      } catch (_) {
        /* Startup finalizes a committed journal. */
      }
      quran.account.reloadBackup();
      content.reloadBackup();
    } catch (_) {
      if (journalWritten && !committed) {
        await recoverHaqRestore(prefs, store: activity.store);
      }
      rethrow;
    } finally {
      if (locked) {
        _unlock();
        activity.changed(scope);
      }
    }
  }
}
