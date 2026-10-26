import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'prayer_models.dart';

class HeadingController extends ChangeNotifier {
  HeadingController({Stream<dynamic> Function(Map<String, double>)? readings})
    : readings =
          readings ??
          ((args) => const EventChannel(
            'com.haqfoundation.haq_app/heading',
          ).receiveBroadcastStream(args));
  final Stream<dynamic> Function(Map<String, double>) readings;
  StreamSubscription<dynamic>? _subscription;
  Timer? _stale;
  bool _disposed = false;
  double? degrees;
  int accuracy = 0;
  bool trueNorth = false;
  String? error;
  bool get usable =>
      degrees != null && accuracy >= 2 && trueNorth && error == null;
  void start(PrayerLocation place) {
    stop();
    if (_disposed) return;
    error = 'بانتظار قراءة البوصلة…';
    notifyListeners();
    void expire() {
      if (!_disposed) {
        degrees = null;
        error = 'قراءة البوصلة غير متاحة أو توقفت. أعد المحاولة.';
        notifyListeners();
      }
    }

    _stale = Timer(const Duration(seconds: 8), expire);
    _subscription = readings({'lat': place.latitude, 'lng': place.longitude})
        .listen(
          (event) {
            if (_disposed || event is! Map) return;
            final raw = event['degrees'];
            if (raw is! num || !raw.isFinite || raw < 0 || raw >= 360) return;
            final next = raw.toDouble();
            degrees = degrees == null
                ? next
                : (degrees! + headingDifference(next, degrees!) * .25 + 360) %
                      360;
            accuracy = event['accuracy'] is int ? event['accuracy'] as int : 0;
            trueNorth = event['trueNorth'] == true;
            error = null;
            _stale?.cancel();
            _stale = Timer(const Duration(seconds: 5), expire);
            notifyListeners();
          },
          onError: (Object e) {
            if (!_disposed) {
              degrees = null;
              error =
                  'حساس الاتجاه غير متاح. يمكنك قراءة زاوية القبلة من الشمال الحقيقي دون سهم حي.';
              _stale?.cancel();
              notifyListeners();
            }
          },
          onDone: expire,
        );
  }

  void stop() {
    _stale?.cancel();
    _stale = null;
    final old = _subscription;
    _subscription = null;
    unawaited(old?.cancel());
    degrees = null;
    accuracy = 0;
    trueNorth = false;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
