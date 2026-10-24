import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sql;

import '../../quran/data/quran_sync.dart' show operationId, QuranSyncLedger;
import 'activity_models.dart';

String religiousActivityScope(String? owner) {
  if (owner == null) return 'guest';
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(owner)) {
    throw const FormatException('Invalid account');
  }
  return 'account.$owner';
}

void _scope(String scope) {
  if (scope != 'guest' && !RegExp(r'^account\.[1-9][0-9]*$').hasMatch(scope)) {
    throw const FormatException('Invalid owner scope');
  }
}

/// A new SQLite file. Existing Quran/religious preferences remain authoritative
/// for their old features; a checksummed snapshot is retained without converting
/// saved catalog IDs into invented free-text dhikr or counter targets.
class ReligiousActivityStore {
  ReligiousActivityStore._(this.database);
  final sql.Database database;

  static Future<ReligiousActivityStore> open({
    sql.DatabaseFactory? factory,
    String? path,
  }) async {
    final driver = factory ?? sql.databaseFactory;
    final location =
        path ??
        '${await driver.getDatabasesPath()}/haq_religious_activity_v1.sqlite';
    final database = await driver.openDatabase(
      location,
      options: sql.OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE activity_meta (scope TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY (scope, name))',
          );
          await db.execute(
            'CREATE TABLE personal_server (scope TEXT NOT NULL, entity_key TEXT NOT NULL, record TEXT NOT NULL, PRIMARY KEY (scope, entity_key))',
          );
          await db.execute(
            'CREATE TABLE personal_pending (scope TEXT NOT NULL, entity_key TEXT NOT NULL, operation TEXT NOT NULL, PRIMARY KEY (scope, entity_key))',
          );
          await db.execute('''CREATE TABLE activity_events (
          sequence INTEGER PRIMARY KEY AUTOINCREMENT,
          scope TEXT NOT NULL, event_id TEXT NOT NULL, session_id TEXT NOT NULL,
          subject_id TEXT NOT NULL, epoch TEXT NOT NULL, kind TEXT NOT NULL, amount INTEGER NOT NULL,
          local_day TEXT NOT NULL, reverses TEXT, payload TEXT NOT NULL,
          acknowledged INTEGER NOT NULL DEFAULT 0,
          UNIQUE (scope, event_id), UNIQUE (scope, reverses)
        )''');
          await db.execute(
            'CREATE INDEX activity_session ON activity_events (scope, session_id, epoch, subject_id)',
          );
          await db.execute(
            'CREATE INDEX activity_pending ON activity_events (scope, acknowledged, sequence)',
          );
          await db.execute(
            'CREATE INDEX activity_day ON activity_events (scope, local_day, kind)',
          );
        },
      ),
    );
    final store = ReligiousActivityStore._(database);
    await database.transaction((tx) async {
      if (await store._meta(tx, 'global', 'device_id') == null) {
        await store._setMeta(tx, 'global', 'device_id', operationId());
      }
    });
    return store;
  }

  Future<String> get deviceId async =>
      (await _meta(database, 'global', 'device_id'))!;
  Future<void> close() => database.close();

  Future<String?> _meta(
    sql.DatabaseExecutor tx,
    String scope,
    String name,
  ) async {
    final rows = await tx.query(
      'activity_meta',
      columns: ['value'],
      where: 'scope = ? AND name = ?',
      whereArgs: [scope, name],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> _setMeta(
    sql.DatabaseExecutor tx,
    String scope,
    String name,
    String value,
  ) async {
    await tx.insert('activity_meta', {
      'scope': scope,
      'name': name,
      'value': value,
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<void> snapshotLegacy(
    String scope,
    SharedPreferences preferences,
  ) async {
    _scope(scope);
    await database.transaction((tx) async {
      if (await _meta(tx, scope, 'legacy.v1') != null) return;
      final owner = scope == 'guest'
          ? null
          : scope.substring('account.'.length);
      final keys = [
        owner == null ? 'quran.state.v1' : 'quran.state.v1.account.$owner',
        'religious.state.v1.$scope',
        'religious.sync.v1.$scope',
      ];
      final values = {
        for (final key in keys)
          if (preferences.containsKey(key)) key: preferences.get(key),
      };
      final encoded = jsonEncode(values);
      await _setMeta(
        tx,
        scope,
        'legacy.v1',
        jsonEncode({
          'schema': 1,
          'sha256': sha256.convert(utf8.encode(encoded)).toString(),
          'values': values,
        }),
      );
    });
  }

  Future<Map<String, dynamic>?> legacySnapshot(String scope) async {
    _scope(scope);
    final value = await _meta(database, scope, 'legacy.v1');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<QuranSyncLedger> _ledger(sql.DatabaseExecutor tx, String scope) async {
    final server = await tx.query(
      'personal_server',
      where: 'scope = ?',
      whereArgs: [scope],
    );
    final pending = await tx.query(
      'personal_pending',
      where: 'scope = ?',
      whereArgs: [scope],
      orderBy: 'rowid',
    );
    return QuranSyncLedger(
      stored: {
        'server': {
          for (final row in server)
            row['entity_key'] as String: jsonDecode(row['record'] as String),
        },
        'pending': {
          for (final row in pending)
            row['entity_key'] as String: jsonDecode(row['operation'] as String),
        },
      },
    );
  }

  Future<void> _saveLedger(
    sql.DatabaseExecutor tx,
    String scope,
    QuranSyncLedger ledger,
  ) async {
    final batch = tx.batch();
    batch.delete('personal_server', where: 'scope = ?', whereArgs: [scope]);
    batch.delete('personal_pending', where: 'scope = ?', whereArgs: [scope]);
    for (final entry in ledger.server.entries) {
      batch.insert('personal_server', {
        'scope': scope,
        'entity_key': entry.key,
        'record': jsonEncode(entry.value),
      });
    }
    for (final entry in ledger.pending.entries) {
      batch.insert('personal_pending', {
        'scope': scope,
        'entity_key': entry.key,
        'operation': jsonEncode(entry.value),
      });
    }
    await batch.commit(noResult: true);
  }

  PersonalEntity _entity(String key, Object? value) {
    final parts = key.split(':');
    if (parts.length != 2 || value is! Map) {
      throw const FormatException('Invalid personal record');
    }
    final entity = PersonalEntity.fromJson(
      PersonalEntityKind.values.byName(parts.first),
      Map<String, dynamic>.from(value),
    );
    if (entity.key != key) {
      throw const FormatException('Mismatched personal identifier');
    }
    return entity;
  }

  Future<List<PersonalEntity>> entities(
    String scope, {
    PersonalEntityKind? kind,
  }) async {
    _scope(scope);
    final ledger = await _ledger(database, scope);
    return [
      for (final entry in ledger.visible.entries)
        if (kind == null || entry.key.startsWith('${kind.name}:'))
          _entity(entry.key, entry.value),
    ];
  }

  Future<PersonalEntity?> entity(String scope, String key) async {
    _scope(scope);
    final pending = await database.query(
      'personal_pending',
      columns: ['operation'],
      where: 'scope = ? AND entity_key = ?',
      whereArgs: [scope, key],
    );
    final server = pending.isEmpty
        ? await database.query(
            'personal_server',
            columns: ['record'],
            where: 'scope = ? AND entity_key = ?',
            whereArgs: [scope, key],
          )
        : const <Map<String, Object?>>[];
    if (pending.isEmpty && server.isEmpty) return null;
    final record =
        jsonDecode(
              (pending.isNotEmpty
                      ? pending.single['operation']
                      : server.single['record'])
                  as String,
            )
            as Map<String, dynamic>;
    return record['deleted'] == true ? null : _entity(key, record['value']);
  }

  Future<void> save(String scope, PersonalEntity entity) async {
    _scope(scope);
    await database.transaction((tx) async {
      final ledger = await _ledger(tx, scope);
      ledger.record({...ledger.visible, entity.key: entity.toJson()});
      await _saveLedger(tx, scope, ledger);
    });
  }

  /// Membership changes and deletion share one transaction. No orphaned custom
  /// references are left behind if a write fails halfway through an edit.
  Future<void> apply(
    String scope, {
    List<PersonalEntity> upserts = const [],
    List<String> deletes = const [],
  }) async {
    _scope(scope);
    for (final key in deletes) {
      final parts = key.split(':');
      if (parts.length != 2 ||
          !PersonalEntityKind.values.any((v) => v.name == parts.first)) {
        throw const FormatException('Invalid deletion key');
      }
      activityUuid(parts.last);
    }
    await database.transaction((tx) async {
      final ledger = await _ledger(tx, scope);
      final values = ledger.visible;
      for (final key in deletes) {
        values.remove(key);
      }
      for (final entity in upserts) {
        values[entity.key] = entity.toJson();
      }
      ledger.record(values);
      await _saveLedger(tx, scope, ledger);
    });
  }

  Future<void> updateGroup(
    String scope,
    String id,
    PersonalDhikrGroup Function(PersonalDhikrGroup?) change,
  ) async {
    _scope(scope);
    final key = 'group:${activityUuid(id)}';
    await database.transaction((tx) async {
      final ledger = await _ledger(tx, scope);
      final visible = ledger.visible;
      final previous = visible[key];
      final updated = change(
        previous == null
            ? null
            : PersonalDhikrGroup.fromJson(
                Map<String, dynamic>.from(previous as Map),
              ),
      );
      if (updated.key != key) throw StateError('Group identity changed');
      ledger.record({...visible, key: updated.toJson()});
      await _saveLedger(tx, scope, ledger);
    });
  }

  Future<Map<String, int>> counts(
    String scope,
    String sessionId,
    String epoch,
  ) async {
    _scope(scope);
    final rows = await database.rawQuery(
      '''SELECT e.subject_id, SUM(e.amount) AS total FROM activity_events e
      WHERE e.scope = ? AND e.session_id = ? AND e.epoch = ? AND e.kind = 'count'
      AND NOT EXISTS (SELECT 1 FROM activity_events u WHERE u.scope = e.scope AND u.reverses = e.event_id)
      GROUP BY e.subject_id''',
      [scope, activityUuid(sessionId), activityUuid(epoch)],
    );
    return {
      for (final row in rows) row['subject_id'] as String: row['total'] as int,
    };
  }

  Future<void> remove(String scope, PersonalEntityKind kind, String id) async {
    _scope(scope);
    final key = '${kind.name}:${activityUuid(id)}';
    await database.transaction((tx) async {
      final ledger = await _ledger(tx, scope);
      final values = ledger.visible..remove(key);
      ledger.record(values);
      await _saveLedger(tx, scope, ledger);
    });
  }

  Future<List<Map<String, dynamic>>> pendingPersonal(String scope) async {
    _scope(scope);
    return (await _ledger(database, scope)).pending.values
        .take(250)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
  }

  Future<void> acceptPersonal(
    String scope,
    Map<String, dynamic> response,
    List<Map<String, dynamic>> sent,
  ) async {
    _scope(scope);
    // Validate the complete response before writing or acknowledging anything.
    for (final entry in (response['entities'] as Map).entries) {
      final record = entry.value as Map;
      final parts = (entry.key as String).split(':');
      if (parts.length != 2 ||
          !PersonalEntityKind.values.any((kind) => kind.name == parts.first) ||
          activityUuid(parts.last) != parts.last ||
          record['deleted'] is! bool ||
          record['revision'] is! int ||
          (record['revision'] as int) < 0 ||
          record['deleted'] == true && record['value'] != null) {
        throw const FormatException('Invalid personal sync response');
      }
      if (record['deleted'] != true) {
        _entity(entry.key as String, record['value']);
      }
    }
    await database.transaction((tx) async {
      final ledger = await _ledger(tx, scope);
      ledger.accept(response, sent);
      await _saveLedger(tx, scope, ledger);
    });
  }

  Future<bool> _append(
    sql.DatabaseExecutor tx,
    String scope,
    ReligiousActivityEvent event, {
    bool acknowledged = false,
  }) async {
    final payload = jsonEncode(event.toJson());
    final rows = await tx.query(
      'activity_events',
      where: 'scope = ? AND event_id = ?',
      whereArgs: [scope, event.id],
    );
    if (rows.isNotEmpty) {
      if (rows.single['payload'] != payload) {
        throw StateError('Activity identifier reused with different data');
      }
      if (acknowledged) {
        await tx.update(
          'activity_events',
          {'acknowledged': 1},
          where: 'scope = ? AND event_id = ?',
          whereArgs: [scope, event.id],
        );
      }
      return false;
    }
    if (event.kind == ActivityKind.undo) {
      final earlier = await tx.query(
        'activity_events',
        where: 'scope = ? AND reverses = ?',
        whereArgs: [scope, event.reverses],
      );
      if (earlier.isNotEmpty &&
          acknowledged &&
          earlier.single['acknowledged'] == 0) {
        // Two offline devices may undo the same tap. The accepted server undo
        // replaces the redundant pending undo; history still reverses one tap.
        await tx.delete(
          'activity_events',
          where: 'scope = ? AND event_id = ?',
          whereArgs: [scope, earlier.single['event_id']],
        );
      }
      final targets = await tx.query(
        'activity_events',
        where: 'scope = ? AND event_id = ?',
        whereArgs: [scope, event.reverses],
      );
      if (targets.isEmpty) throw StateError('Undo target not available');
      final target = ReligiousActivityEvent.fromJson(
        jsonDecode(targets.single['payload'] as String) as Map<String, dynamic>,
      );
      if (target.kind == ActivityKind.undo ||
          target.kind == ActivityKind.reset ||
          target.kind == ActivityKind.complete ||
          target.sessionId != event.sessionId ||
          target.subjectId != event.subjectId ||
          target.epoch != event.epoch) {
        throw StateError(
          'Undo target belongs to a different session or subject',
        );
      }
    }
    await tx.insert('activity_events', {
      'scope': scope,
      'event_id': event.id,
      'session_id': event.sessionId,
      'subject_id': event.subjectId,
      'epoch': event.epoch,
      'kind': event.kind.name,
      'amount': event.amount,
      'local_day': event.day,
      'reverses': event.reverses,
      'payload': payload,
      'acknowledged': acknowledged ? 1 : 0,
    });
    return true;
  }

  Future<bool> append(String scope, ReligiousActivityEvent event) async {
    _scope(scope);
    return database.transaction((tx) => _append(tx, scope, event));
  }

  Future<int> _count(
    sql.DatabaseExecutor tx,
    String scope,
    String sessionId,
    String subjectId,
    String epoch,
  ) async {
    final rows = await tx.rawQuery(
      '''SELECT COALESCE(SUM(e.amount), 0) AS total FROM activity_events e
      WHERE e.scope = ? AND e.session_id = ? AND e.subject_id = ? AND e.epoch = ? AND e.kind = 'count'
      AND NOT EXISTS (SELECT 1 FROM activity_events u WHERE u.scope = e.scope AND u.reverses = e.event_id)''',
      [scope, sessionId, subjectId, epoch],
    );
    return rows.single['total'] as int;
  }

  Future<int> count(
    String scope,
    String sessionId,
    String subjectId,
    String epoch,
  ) async {
    _scope(scope);
    return _count(
      database,
      scope,
      activityUuid(sessionId),
      activitySubject(subjectId),
      activityUuid(epoch),
    );
  }

  /// The target check and append are one transaction: concurrent taps cannot
  /// overshoot zero. Tasbih can use append() for an independent ascending count.
  Future<bool> appendWithinTarget(
    String scope,
    ReligiousActivityEvent event,
    int target,
  ) async {
    _scope(scope);
    if (event.kind != ActivityKind.count || target < 1) {
      throw ArgumentError('A positive count target is required');
    }
    return database.transaction((tx) async {
      final existing = await tx.query(
        'activity_events',
        where: 'scope = ? AND event_id = ?',
        whereArgs: [scope, event.id],
      );
      if (existing.isNotEmpty) {
        if (existing.single['payload'] != jsonEncode(event.toJson())) {
          throw StateError('Activity identifier reused with different data');
        }
        return false;
      }
      final current = await _count(
        tx,
        scope,
        event.sessionId,
        event.subjectId,
        event.epoch,
      );
      if (current + event.amount > target) return false;
      return _append(tx, scope, event);
    });
  }

  Future<List<ReligiousActivityEvent>> events(
    String scope, {
    String? sessionId,
    String? day,
    bool pendingOnly = false,
    int? limit,
  }) async {
    _scope(scope);
    final conditions = ['scope = ?'];
    final args = <Object?>[scope];
    if (sessionId != null) {
      conditions.add('session_id = ?');
      args.add(activityUuid(sessionId));
    }
    if (day != null) {
      conditions.add('local_day = ?');
      args.add(activityDate(day));
    }
    if (pendingOnly) conditions.add('acknowledged = 0');
    final rows = await database.query(
      'activity_events',
      columns: ['payload'],
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'sequence',
      limit: limit,
    );
    return rows
        .map(
          (row) => ReligiousActivityEvent.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<int> activityCursor(String scope) async {
    _scope(scope);
    return int.parse(await _meta(database, scope, 'activity.cursor') ?? '0');
  }

  Future<void> acceptActivity(
    String scope,
    Map<String, dynamic> response,
  ) async {
    _scope(scope);
    final rows = response['events'] as List;
    final records = rows
        .map(
          (value) => ReligiousActivityEvent.fromJson(
            Map<String, dynamic>.from((value as Map)['event'] as Map),
          ),
        )
        .toList();
    final acknowledged = List<String>.from(
      response['acknowledged'] as List,
    ).map(activityUuid).toList();
    final cursor = response['cursor'] as int;
    await database.transaction((tx) async {
      final previousCursor = int.parse(
        await _meta(tx, scope, 'activity.cursor') ?? '0',
      );
      if (cursor < previousCursor) {
        throw StateError('Activity cursor moved backwards');
      }
      final revision = response['revision'] as int;
      if (revision < cursor ||
          response['has_more'] != (cursor < revision) ||
          cursor != previousCursor + rows.length ||
          rows.length > 500) {
        throw const FormatException('Invalid activity page');
      }
      for (var index = 0; index < rows.length; index++) {
        if ((rows[index] as Map)['revision'] != previousCursor + index + 1) {
          throw const FormatException('Missing activity revision');
        }
      }
      for (final event in records) {
        await _append(tx, scope, event, acknowledged: true);
      }
      for (final id in acknowledged) {
        await tx.update(
          'activity_events',
          {'acknowledged': 1},
          where: 'scope = ? AND event_id = ?',
          whereArgs: [scope, id],
        );
      }
      await _setMeta(tx, scope, 'activity.cursor', '$cursor');
    });
  }

  Future<void> mergeGuestOnce(String accountScope) async {
    _scope(accountScope);
    if (accountScope == 'guest') {
      throw ArgumentError('An account scope is required');
    }
    await database.transaction((tx) async {
      if (await _meta(tx, accountScope, 'guest.imported') == '1') return;
      final guest = await _ledger(tx, 'guest');
      final account = await _ledger(tx, accountScope);
      account.mergeGuest(guest.visible);
      await _saveLedger(tx, accountScope, account);
      final records = await tx.query(
        'activity_events',
        where: 'scope = ?',
        whereArgs: ['guest'],
        orderBy: 'sequence',
      );
      for (final row in records) {
        await _append(
          tx,
          accountScope,
          ReligiousActivityEvent.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        );
      }
      await _setMeta(tx, accountScope, 'guest.imported', '1');
    });
  }
}
