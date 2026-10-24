import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract interface class TasbihSpeech {
  Future<String?> start(
    Object owner, {
    required void Function(String) onFinal,
    required void Function(bool, String?) onStatus,
  });
  Future<void> cancel(Object owner);
}

/// One plugin instance and serialized ownership across all counter screens.
/// Initialization is deferred until an explicit microphone press.
class DeviceTasbihSpeech implements TasbihSpeech {
  static final shared = DeviceTasbihSpeech();
  final _speech = SpeechToText();
  Object? _owner;
  void Function(bool, String?)? _status;
  Future<void> _lane = Future.value();
  int _generation = 0;
  @override
  Future<String?> start(
    Object owner, {
    required void Function(String) onFinal,
    required void Function(bool, String?) onStatus,
  }) async {
    final generation = ++_generation;
    _owner = owner;
    _status = onStatus;
    String? error;
    final job = _lane.then((_) async {
      bool current() => _owner == owner && _generation == generation;
      if (!current()) return;
      await _speech.cancel();
      if (!current()) return;
      final ready = await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
        onStatus: (status) => _status?.call(status == 'listening', null),
        onError: (_) => _status?.call(
          false,
          'تعذّر التعرف على الصوت؛ جرّب مجددًا أو عدّ يدويًا',
        ),
      );
      if (!current()) return;
      if (!ready) {
        error = 'الميكروفون غير متاح أو الإذن مرفوض؛ العدّ اليدوي متاح';
        return;
      }
      final locales = await _speech.locales();
      if (!current()) return;
      final arabic = locales
          .where((locale) => locale.localeId.toLowerCase().startsWith('ar'))
          .firstOrNull;
      if (arabic == null) {
        error =
            'التعرف على العربية غير متاح على هذا الجهاز؛ استخدم العدّ اليدوي';
        return;
      }
      await _speech.listen(
        onResult: (result) {
          if (current() && result.finalResult) onFinal(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: arabic.localeId,
          partialResults: false,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      if (current()) onStatus(_speech.isListening, null);
    });
    _lane = job.catchError((Object _) {
      error = 'التعرف الصوتي غير متاح؛ العدّ اليدوي متاح';
    });
    await _lane;
    return _owner == owner && _generation == generation ? error : null;
  }

  @override
  Future<void> cancel(Object owner) async {
    if (_owner != owner) return;
    _owner = null;
    _status = null;
    _generation++;
    final job = _lane.then((_) => _speech.cancel());
    _lane = job.catchError((Object _) {});
    await _lane;
  }
}

String normalizeTasbihSpeech(String text) => text
    .toLowerCase()
    .replaceAll(
      RegExp(r'[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed\u0640]'),
      '',
    )
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'[^\u0621-\u063a\u0641-\u064a0-9a-z]+'), ' ')
    .trim();

/// A short recognition session counts its final phrase once. No transcript or
/// microphone recording is persisted. Partial/duplicate callbacks never count.
class TasbihVoice extends ChangeNotifier {
  TasbihVoice(this.speech);
  final TasbihSpeech speech;
  Object? _lease;
  bool active = false, starting = false, _disposed = false;
  String? message;
  Future<void> start(String phrase, Future<void> Function() increment) async {
    await stop();
    if (_disposed) return;
    final lease = Object();
    _lease = lease;
    starting = true;
    message = null;
    notifyListeners();
    var delivered = false;
    final expected = normalizeTasbihSpeech(phrase).split(' ');
    final error = await speech.start(
      lease,
      onStatus: (value, error) {
        if (_disposed || _lease != lease) return;
        active = value;
        message = error;
        notifyListeners();
      },
      onFinal: (words) {
        if (_disposed || _lease != lease || delivered) return;
        delivered = true;
        final spoken = normalizeTasbihSpeech(words).split(' ');
        var matches = 0;
        for (var i = 0; i <= spoken.length - expected.length;) {
          if (listEquals(spoken.sublist(i, i + expected.length), expected)) {
            matches++;
            i += expected.length;
          } else {
            i++;
          }
        }
        // Bound a recognition result so a malformed provider cannot flood writes.
        unawaited(() async {
          // A final result ends this explicit microphone session on every OS,
          // even if its recognizer would otherwise keep listening.
          await speech.cancel(lease);
          for (
            var i = 0;
            i < matches.clamp(0, 50) && _lease == lease && !_disposed;
            i++
          ) {
            await increment();
          }
        }());
        message = matches == 0
            ? 'لم أتعرف على الذكر المختار؛ اضغط الميكروفون للمحاولة'
            : 'تم التعرف على الذكر؛ اضغط الميكروفون للاستماع مجددًا';
        active = false;
        notifyListeners();
      },
    );
    if (_disposed || _lease != lease) return;
    starting = false;
    message = error ?? message;
    notifyListeners();
  }

  Future<void> stop() async {
    final previous = _lease;
    _lease = null;
    active = false;
    starting = false;
    if (!_disposed) notifyListeners();
    if (previous != null) await speech.cancel(previous);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
