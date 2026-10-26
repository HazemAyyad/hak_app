import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../adhkar/data/adhkar_repository.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import 'app_settings.dart';
import 'reminder_plan.dart';
import '../../prayer/data/prayer_controller.dart';

class ReminderDeviceState {
  const ReminderDeviceState({
    this.supported = false,
    this.allowed = false,
    this.overlay = false,
    this.overlayRunning = false,
    this.pending = 0,
    this.platform = 'unsupported',
    this.speech = false,
  });
  factory ReminderDeviceState.fromMap(Map data) => ReminderDeviceState(
    supported: true,
    allowed: data['allowed'] == true,
    overlay: data['overlay'] == true,
    overlayRunning: data['overlayRunning'] == true,
    pending: data['pending'] as int? ?? 0,
    platform: data['platform'] as String? ?? 'unsupported',
    speech: data['speech'] == true,
  );
  final bool supported, allowed, overlay, overlayRunning, speech;
  final int pending;
  final String platform;
}

/// Serializes account switches and edits so an obsolete asynchronous plan can
/// never finish after the current account's cancellation/replacement.
class ReminderController extends ChangeNotifier {
  ReminderController(
    this.activity,
    this.catalog, {
    MethodChannel? channel,
    this.onOpen,
    this.prayer,
  }) : channel =
           channel ??
           const MethodChannel('com.haqfoundation.haq_app/reminders') {
    settings = AppSettings(activity.quran.preferences!, activity.scope);
    settings.addListener(_settingsChanged);
    activity.addListener(_activityChanged);
    prayer?.scheduleChanged.addListener(_changed);
    this.channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        onOpen?.call(call.arguments as String);
      }
    });
  }
  final ReligiousActivityController activity;
  final AdhkarRepository catalog;
  final MethodChannel channel;
  final void Function(String)? onOpen;
  final PrayerController? prayer;
  late AppSettings settings;
  ReminderDeviceState device = const ReminderDeviceState();
  String? error;
  Future<void> _jobs = Future.value();
  Timer? _debounce;
  bool _disposed = false;
  Map<String, String> content = {};
  String? _fingerprint;

  Future<void> initialize() async {
    await reconcile();
    if (_disposed) return;
    try {
      final route = await channel.invokeMethod<String>('pendingOpen');
      if (!_disposed && route != null) onOpen?.call(route);
    } on MissingPluginException {
      /* Desktop/test: no native capability. */
    }
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(reconcile()),
    );
  }

  void _settingsChanged() {
    prayer?.tick();
    _changed();
  }

  void _activityChanged() {
    if (_disposed) return;
    if (settings.scope != activity.scope) {
      settings.removeListener(_settingsChanged);
      settings.dispose();
      settings = AppSettings(activity.quran.preferences!, activity.scope)
        ..addListener(_settingsChanged);
      content = {};
      device = const ReminderDeviceState();
      _fingerprint = null;
      // Cancel private notifications immediately, before reading another scope.
      unawaited(reconcile());
      notifyListeners();
    } else {
      _changed();
    }
  }

  Future<void> reconcile({bool force = false}) {
    final job = _jobs.then((_) async {
      if (_disposed) return;
      final scope = activity.scope, config = settings;
      try {
        // The native side stores a scope too; switching it clears delivered,
        // pending, snoozed and overlay content before new private data is read.
        try {
          await channel.invokeMethod<void>('scope', scope);
          final state = await channel.invokeMapMethod<String, dynamic>(
            'status',
          );
          if (_disposed || activity.scope != scope) return;
          device = ReminderDeviceState.fromMap(state ?? {});
        } on MissingPluginException {
          /* Still load real preview content. */
        }
        final entities = await activity.store.entities(scope);
        final history = await activity.store.events(scope);
        if (_disposed || activity.scope != scope) return;
        content = {
          for (final item in catalog.items.values) item.id: item.text,
          for (final item in entities.whereType<PersonalDhikr>())
            item.id: item.text,
        };
        final selected = config.content
            .where(content.containsKey)
            .map((id) => content[id]!)
            .toList();
        final plan = [
          ...reminderPlan(
            config,
            entities,
            history,
          ).where((j) => j.interval == null || selected.isNotEmpty),
          if (config.flag('enabled') && prayer?.scope == scope)
            ...prayer!.reminderJobs(),
        ];
        final payload = <String, Object>{
          'scope': scope,
          'jobs': plan.map((j) => j.toJson()).toList(),
          'sound': config.flag('sound'),
          'snooze': config.number('snooze', 10),
          'startup': config.flag('startup'),
          'type': config.text('type', 'center'),
          'smartItems': selected,
          'ordered': config.flag('ordered'),
          'speech': config.flag('speech'),
          'transparent': config.flag('transparent'),
          'position': config.text('position', 'top'),
          'font': config.text('font', 'Cairo'),
          'fontSize': config.number('fontSize', 20),
          'hide': config.number('hide', -1),
          'background': config.number('background', 0xFF2A8C82),
          'border': config.number('border', 0xFFC7A45A),
          'textColor': config.number('textColor', 0xFFFFFCF7),
          'effects': config.flag('effects'),
          'animation': config.text('animation', 'zoom'),
        };
        final fingerprint = jsonEncode(payload);
        payload['signature'] = sha256
            .convert(utf8.encode(fingerprint))
            .toString();
        if (force || fingerprint != _fingerprint) {
          await channel.invokeMethod<void>('replace', payload);
          _fingerprint = fingerprint;
        }
        final state = await channel.invokeMapMethod<String, dynamic>('status');
        if (_disposed || activity.scope != scope) return;
        device = ReminderDeviceState.fromMap(state ?? {});
        error = state?['failed'] == true
            ? 'تعذّر تنفيذ بعض التذكيرات على الجهاز. أعد تحديث الجدولة.'
            : null;
      } on MissingPluginException {
        device = const ReminderDeviceState();
      } catch (_) {
        error =
            'الإعدادات محفوظة، لكن تعذّر تحديث جدولة التذكيرات. أعد المحاولة.';
      }
      if (!_disposed) notifyListeners();
    });
    _jobs = job;
    return job;
  }

  Future<void> action(String name) async {
    if (_disposed) return;
    try {
      await settings.flush();
      await reconcile();
      if (_disposed) return;
      await channel.invokeMethod<void>(name);
      if (!_disposed) await reconcile();
    } on MissingPluginException {
      if (!_disposed) {
        device = const ReminderDeviceState();
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) {
        error = 'تعذّر تنفيذ الطلب على الجهاز؛ تحقق من الصلاحيات.';
        notifyListeners();
      }
    }
  }

  Future<void> flush() async {
    await settings.flush();
    await _jobs;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    activity.removeListener(_activityChanged);
    prayer?.scheduleChanged.removeListener(_changed);
    settings.removeListener(_settingsChanged);
    settings.dispose();
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
