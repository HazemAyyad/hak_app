import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../quran/data/quran_controller.dart';
import 'activity_models.dart';
import 'activity_store.dart';
import 'activity_sync.dart';

/// Created only when a new religious feature is opened. Startup and the
/// existing Quran/preferences paths do not need to initialize another DB.
class ReligiousActivityController extends ChangeNotifier {
  ReligiousActivityController._(this.quran, this.store) {
    syncClient = ReligiousActivitySync(store: store, session: _session);
    quran.account.addListener(_accountChanged);
    _retry = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(sync()),
    );
  }
  final QuranController quran;
  final ReligiousActivityStore store;
  late final ReligiousActivitySync syncClient;
  Timer? _retry;
  bool _disposed = false;
  String get scope =>
      religiousActivityScope(quran.account.profile?['id'].toString());
  String? get syncError => syncClient.errors[scope];

  static Future<ReligiousActivityController> open(QuranController quran) async {
    final store = await ReligiousActivityStore.open();
    final controller = ReligiousActivityController._(quran, store);
    try {
      await store.snapshotLegacy(controller.scope, quran.preferences!);
      unawaited(controller.sync());
      return controller;
    } catch (_) {
      controller.dispose();
      rethrow;
    }
  }

  ActivityAccountSession? _session() {
    final id = quran.account.profile?['id'].toString(),
        token = quran.account.token;
    if (id == null || token == null) return null;
    return ActivityAccountSession(
      id,
      token,
      mergeGuest:
          quran.preferences!.getBool('religious.activity.mergeGuest.$id') ==
          true,
    );
  }

  void _accountChanged() {
    if (_disposed) return;
    notifyListeners();
    unawaited(sync());
  }

  Future<void> sync() async {
    await syncClient.sync();
    if (!_disposed) notifyListeners();
  }

  Future<void> save(PersonalEntity entity) async {
    final captured = scope;
    await store.snapshotLegacy(captured, quran.preferences!);
    await store.save(captured, entity);
    if (!_disposed && scope == captured) {
      notifyListeners();
      unawaited(sync());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    syncClient.disposed = true;
    syncClient.dio.close(force: true);
    _retry?.cancel();
    quran.account.removeListener(_accountChanged);
    unawaited(store.close());
    super.dispose();
  }
}
