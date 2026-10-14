import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/settings_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppAppearance appearance;
  late QuranController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appearance = AppAppearance(await SharedPreferences.getInstance());
    FlutterSecureStorage.setMockInitialValues({});
    controller = QuranController(
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      preferences: await SharedPreferences.getInstance(),
    );
    await controller.load();
  });
  tearDown(() {
    controller.dispose();
    appearance.dispose();
  });

  testWidgets('نوع الخط يتغير من الإعدادات ويحفظ بعد إعادة التشغيل', (
    tester,
  ) async {
    await tester.pumpWidget(
      HaqApp(
        showStartup: false,
        appearance: appearance,
        quranController: controller,
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المظهر وإعدادات العرض'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تجوال'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تجوال'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.text('تجوال')),
      ).textTheme.bodyMedium!.fontFamily,
      'Tajawal',
    );
    final restored = AppAppearance(appearance.preferences);
    expect(restored.font, AppFont.tajawal);
    restored.dispose();
    await tester.ensureVisible(find.text('خط الجهاز'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خط الجهاز'));
    await tester.pumpAndSettle();
    expect(appearance.font, AppFont.system);
  });

  test('قيمة خط غير معروفة تعود إلى القاهرة', () async {
    await appearance.preferences.setString('appearance.font', 'missing-font');
    final restored = AppAppearance(appearance.preferences);
    expect(restored.font, AppFont.cairo);
    restored.dispose();
  });

  testWidgets('تعرض الصفحة الرئيسية الأساسية', (tester) async {
    await tester.pumpWidget(
      HaqApp(
        showStartup: false,
        appearance: appearance,
        quranController: controller,
      ),
    );

    expect(find.text('أحمد محمد'), findsOneWidget);
    expect(find.text('الصلاة القادمة'), findsOneWidget);
    expect(find.text('القرآن الكريم'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });

  testWidgets('تفتح الإعدادات وصفحة فرعية من قسم المزيد', (tester) async {
    await tester.pumpWidget(
      HaqApp(
        showStartup: false,
        appearance: appearance,
        quranController: controller,
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    expect(find.text('كل ما تحتاجه في مكان واحد'), findsOneWidget);

    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.text('إعدادات التطبيق'), findsOneWidget);
    expect(find.text('الحساب والمزامنة'), findsOneWidget);

    await tester.tap(find.text('الحساب والمزامنة'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الدخول'), findsAtLeastNWidgets(1));
  });

  testWidgets('اختيار المظهر يغير المسارات ويحفظ الاختيار وحجم الخط', (
    tester,
  ) async {
    await tester.pumpWidget(
      HaqApp(
        showStartup: false,
        appearance: appearance,
        quranController: controller,
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المظهر وإعدادات العرض'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('داكن'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('داكن'))).brightness,
      Brightness.dark,
    );
    expect(appearance.preferences.getString('appearance.mode'), 'dark');
    await appearance.setFontScale(1.15);
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('داكن'))).scale(10),
      closeTo(11.5, .01),
    );
    final restored = AppAppearance(appearance.preferences);
    expect(restored.mode, ThemeMode.dark);
    expect(restored.fontScale, 1.15);
    restored.dispose();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new).last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('إعدادات التطبيق'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new).last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.text('كل ما تحتاجه في مكان واحد')),
      ).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('الرئيسية'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('أحمد محمد'))).brightness,
      Brightness.dark,
    );

    await appearance.setMode(ThemeMode.system);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('أحمد محمد'))).brightness,
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('أحمد محمد'))).brightness,
      Brightness.dark,
    );
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('صفحات الإعدادات دون تجاوز على شاشة ضيقة ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await appearance.setMode(mode);
      await appearance.setFontScale(1.2);
      await tester.pumpWidget(
        HaqApp(
          showStartup: false,
          appearance: appearance,
          quranController: controller,
        ),
      );
      for (final kind in SettingKind.values) {
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsDetailPage(kind: kind),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: kind.name);
        navigator.pop();
        await tester.pumpAndSettle();
      }
    });
  }
}
