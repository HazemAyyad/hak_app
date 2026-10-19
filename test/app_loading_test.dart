import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_loading.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/presentation/quran_host.dart';
import 'package:haq_app/features/quran/data/quran_audio.dart';
import 'package:haq_app/features/quran/presentation/quran_audio_pages.dart';

class DeferredQuranController extends QuranController {
  void fail() {
    loading = false;
    loadError = StateError('offline');
    notifyListeners();
  }
}

class DeferredPickerMedia extends QuranMedia {
  DeferredPickerMedia()
    : super(
        repository: () => throw UnimplementedError(),
        preferences: () => throw UnimplementedError(),
      );
  final ready = Completer<void>();
  int attempts = 0;
  @override
  Future<void> initialize() {
    attempts++;
    return ready.future;
  }
}

void main() {
  testWidgets(
    'reciter picker opens while preparing and offers retry on failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final appearance = AppAppearance(await SharedPreferences.getInstance());
      final media = DeferredPickerMedia();
      addTearDown(appearance.dispose);
      addTearDown(media.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Scaffold(body: QuranReciterPicker(media: media)),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AppLoadingSkeleton), findsOneWidget);
      expect(media.attempts, 1);
      media.ready.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.byType(AppLoadingSkeleton), findsNothing);
      await tester.tap(find.text('إعادة تحميل قائمة القراء'));
      await tester.pumpAndSettle();
      expect(media.attempts, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('page placeholders fit narrow screens with large RTL text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: AppLoadingSkeleton(label: 'جارٍ تحميل صفحة المصحف'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Quran host keeps skeleton while waiting and replaces it on failure',
    (tester) async {
      final controller = DeferredQuranController();
      addTearDown(controller.dispose);
      SharedPreferences.setMockInitialValues({});
      final appearance = AppAppearance(await SharedPreferences.getInstance());
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: QuranHost(
              controller: controller,
              onFullscreenChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AppLoadingSkeleton), findsOneWidget);
      expect(controller.loading, isTrue);
      controller.fail();
      await tester.pump();
      expect(find.byType(AppLoadingSkeleton), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
