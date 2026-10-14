import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';

void main() {
  test('guest union respects tombstones and existing server preferences', () {
    final ledger = QuranSyncLedger(
      stored: {
        'server': {
          'favorite:2:2': {'value': null, 'deleted': true, 'revision': 8},
          'preferences': {
            'value': {'mode': 'pages'},
            'deleted': false,
            'revision': 4,
          },
        },
      },
    );
    ledger.mergeGuest({
      'favorite:2:2': 'old',
      'bookmark:2:3': 'new',
      'preferences': {'mode': 'ayah'},
    });
    expect(ledger.visible.containsKey('favorite:2:2'), isFalse);
    expect(ledger.visible['preferences']['mode'], 'pages');
    expect(ledger.pending.keys, ['bookmark:2:3']);
  });
  test(
    'offline deletion survives restart and is not resurrected by a stale pull',
    () {
      final ledger = QuranSyncLedger(
        stored: {
          'server': {
            'favorite:2:3': {'value': 'saved', 'deleted': false, 'revision': 1},
          },
        },
      );
      ledger.record({});
      final restored = QuranSyncLedger(stored: ledger.toJson());
      expect(restored.visible, isEmpty);
      expect(restored.pending['favorite:2:3']['deleted'], isTrue);
      restored.accept({
        'acknowledged': [],
        'conflicts': [],
        'entities': ledger.server,
      }, []);
      expect(restored.visible, isEmpty);
    },
  );
  test('acknowledging an upload preserves and rebases a newer local edit', () {
    final ledger = QuranSyncLedger();
    ledger.change('preferences', {'mode': 'ayah'});
    final sent = Map<String, dynamic>.from(
      ledger.pending['preferences'] as Map,
    );
    ledger.change('preferences', {'mode': 'pages'});
    ledger.accept(
      {
        'acknowledged': [sent['id']],
        'conflicts': [],
        'entities': {
          'preferences': {
            'value': sent['value'],
            'deleted': false,
            'revision': 9,
          },
        },
      },
      [sent],
    );
    expect(ledger.visible['preferences']['mode'], 'pages');
    expect(ledger.pending['preferences']['base_revision'], 9);
    expect(ledger.pending['preferences']['id'], isNot(sent['id']));
  });
  test('an acknowledged conflict removes only that pending operation', () {
    final ledger = QuranSyncLedger();
    ledger.change('favorite:2:3', 'add');
    final sent = Map<String, dynamic>.from(
      ledger.pending['favorite:2:3'] as Map,
    );
    ledger.accept(
      {
        'acknowledged': [sent['id']],
        'conflicts': ['favorite:2:3'],
        'entities': {
          'favorite:2:3': {'value': null, 'deleted': true, 'revision': 7},
        },
      },
      [sent],
    );
    expect(ledger.visible, isEmpty);
    expect(ledger.pending, isEmpty);
    expect(ledger.server['favorite:2:3']['revision'], 7);
  });
}
