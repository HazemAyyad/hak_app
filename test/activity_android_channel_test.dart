import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/religious_activity/data/activity_store.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tekartik.sqflite');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = call.arguments as Map? ?? {};
          final sql = args['sql'] as String? ?? '';
          if (call.method == 'openDatabase') return 731;
          if (call.method == 'execute' &&
              sql.startsWith('PRAGMA busy_timeout')) {
            throw PlatformException(
              code: 'sqlite_error',
              message:
                  'Queries can be performed using SQLiteDatabase query or rawQuery methods only.',
            );
          }
          if (call.method == 'query') {
            if (sql == 'PRAGMA user_version') {
              return {
                'columns': ['user_version'],
                'rows': [
                  [2],
                ],
              };
            }
            if (sql.startsWith('PRAGMA busy_timeout')) {
              return {
                'columns': ['timeout'],
                'rows': [
                  [5000],
                ],
              };
            }
            if (sql.contains('activity_meta')) {
              return {
                'columns': ['value'],
                'rows': [
                  ['existing-device-id'],
                ],
              };
            }
            throw StateError('Unexpected query: $sql');
          }
          if (call.method == 'execute' || call.method == 'closeDatabase')
            return null;
          throw StateError('Unexpected native call: ${call.method}');
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'Android sqflite opens existing activity storage without executing a row-returning PRAGMA or resetting data',
    () async {
      final store = await ReligiousActivityStore.open(
        factory: databaseFactorySqflitePlugin,
        path: ':memory:',
      );
      expect(await store.deviceId, 'existing-device-id');
      await store.close();
      expect(
        calls.any(
          (c) =>
              c.method == 'query' &&
              (c.arguments as Map)['sql'] == 'PRAGMA busy_timeout = 5000',
        ),
        true,
      );
      expect(calls.where((c) => c.method == 'deleteDatabase'), isEmpty);
      expect(
        calls
            .where((c) => c.method == 'execute')
            .every(
              (c) => !(c.arguments as Map)['sql'].toString().contains(
                'CREATE TABLE',
              ),
            ),
        true,
      );
    },
  );
}
