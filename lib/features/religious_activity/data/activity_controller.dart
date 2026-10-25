import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../quran/data/quran_controller.dart';
import 'activity_models.dart';
import 'activity_store.dart';
import 'activity_sync.dart';

/// Opened lazily by a religious section or the home journey summary. Existing
/// Quran preferences and downloads retain their independent storage paths.
class ReligiousActivityController extends ChangeNotifier {
  ReligiousActivityController._(
    this.quran,
    this.store,
    this.enableSync,
    this._ownsStore,
  ) {
    syncClient = ReligiousActivitySync(store: store, session: _session);
    quran.account.addListener(_accountChanged);
    if (enableSync) {
      _retry = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(sync()),
      );
    }
  }
  final QuranController quran;
  final ReligiousActivityStore store;
  final bool enableSync;
  final bool _ownsStore;
  late final ReligiousActivitySync syncClient;
  Timer? _retry, _debounce;
  bool _disposed = false;
  String get scope =>
      religiousActivityScope(quran.account.profile?['id'].toString());
  String? get syncError => syncClient.errors[scope];

  static Future<ReligiousActivityController> open(
    QuranController quran, {
    ReligiousActivityStore? store,
    bool enableSync = true,
  }) async {
    final storage = store ?? await ReligiousActivityStore.open();
    final controller = ReligiousActivityController._(
      quran,
      storage,
      enableSync,
      store == null,
    );
    try {
      await storage.snapshotLegacy(controller.scope, quran.preferences!);
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
    if (!enableSync) return;
    await syncClient.sync();
    if (!_disposed) notifyListeners();
  }

  void changed(String capturedScope) {
    if (_disposed || scope != capturedScope) return;
    notifyListeners();
    _debounce?.cancel();
    if (enableSync) {
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
    }
  }

  Future<void> save(PersonalEntity entity) async {
    final captured = scope;
    await store.snapshotLegacy(captured, quran.preferences!);
    await store.save(captured, entity);
    if (!_disposed && scope == captured) {
      changed(captured);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    syncClient.disposed = true;
    syncClient.dio.close(force: true);
    _retry?.cancel();
    _debounce?.cancel();
    quran.account.removeListener(_accountChanged);
    if (_ownsStore) unawaited(store.close());
    super.dispose();
  }
}
