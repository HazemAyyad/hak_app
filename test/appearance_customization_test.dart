import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/settings_pages.dart';
import 'package:haq_app/features/quran/presentation/quran_widgets.dart';
import 'package:haq_app/features/religious_content/presentation/religious_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/visual_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUpAll(() async {
    await loadVisualAuditFonts();
    await (FontLoader(
      'QuranUI',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test(
    'ten accents survive reopening; unknown saved color uses original',
    () async {
      final appearance = AppAppearance(prefs);
      addTearDown(appearance.dispose);
      expect(AppColor.values.length, 10);
      for (final color in AppColor.values) {
        await appearance.setColor(color);
        final reopened = AppAppearance(prefs);
        expect(reopened.color, color);
        reopened.dispose();
      }
      await prefs.setString('appearance.color', 'retired-color');
      final recovered = AppAppearance(prefs);
      expect(recovered.color, AppColor.haq);
      recovered.dispose();
    },
  );

  test(
    'daily content follows custom boundaries, independent of manual theme',
    () async {
      var now = DateTime(2026, 10, 29, 7, 29);
      final appearance = AppAppearance(prefs, clock: () => now);
      addTearDown(appearance.dispose);
      await appearance.setSchedule(day: 450, night: 1035);
      await appearance.setMode(ThemeMode.light);
      expect(appearance.dailyAdhkarGroup, 'daily:evening');
      now = DateTime(2026, 10, 29, 7, 30);
      expect(appearance.dailyAdhkarGroup, 'daily:morning');
      now = DateTime(2026, 10, 29, 17, 14);
      expect(appearance.isDaytime, true);
      now = DateTime(2026, 10, 29, 17, 15);
      expect(appearance.dailyAdhkarGroup, 'daily:evening');
      expect(appearance.effectiveMode, ThemeMode.light);
      await appearance.setSchedule(day: 1200, night: 360);
      now = DateTime(2026, 10, 29, 23, 59);
      expect(appearance.isDaytime, true);
      now = DateTime(2026, 10, 30);
      expect(appearance.isDaytime, true);
      now = DateTime(2026, 10, 30, 6);
      expect(appearance.isDaytime, false);
      final reopened = AppAppearance(prefs, clock: () => now);
      expect(reopened.dayStart, 1200);
      expect(reopened.nightStart, 360);
      expect(reopened.dailyAdhkarGroup, 'daily:evening');
      reopened.dispose();
    },
  );

  testWidgets(
    'home switches on the clock with a manual theme, and refreshes after resume',
    (tester) async {
      var now = DateTime(2026, 10, 29, 17, 59);
      final appearance = AppAppearance(prefs, clock: () => now);
      await appearance.setMode(ThemeMode.light);
      await tester.pumpWidget(_surface(appearance, const DhikrCard()));
      expect(find.text('أذكار الصباح'), findsOneWidget);
      now = DateTime(2026, 10, 29, 18);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('أذكار المساء'), findsOneWidget);
      expect(find.byIcon(Icons.nights_stay_outlined), findsOneWidget);
      final eveningImage = tester
          .widgetList<Image>(find.byType(Image))
          .any(
            (image) =>
                image.image == const AssetImage('assets/home/lantern.png'),
          );
      expect(eveningImage, true);
      now = DateTime(2026, 10, 30, 6);
      appearance.refreshTime();
      await tester.pump();
      expect(find.text('أذكار الصباح'), findsOneWidget);
      // Changing the saved schedule also updates content immediately.
      await appearance.setSchedule(day: 600, night: 1200);
      await tester.pump();
      expect(find.text('أذكار المساء'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'home shortcuts and decorative icons follow every accent ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final appearance = AppAppearance(
          prefs,
          clock: () => DateTime(2026, 10, 29, 10),
        );
        await appearance.setMode(
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
        final boundary = GlobalKey();
        for (final color in [...AppColor.values, AppColor.haq]) {
          await appearance.setColor(color);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: _surface(
                appearance,
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: const [
                        QuickServices(),
                        PrayerCard(),
                        DhikrCard(),
                        JourneyCards(),
                        FridayCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final accent = AppAccent(color, brightness);
          for (final index in [1, 4, 5, 6, 7]) {
            final tile = find.byKey(ValueKey('home-service-$index'));
            final icon = tester.widget<Icon>(
              find.descendant(of: tile, matching: find.byType(Icon)),
            );
            final material = tester.widget<Material>(
              find.ancestor(of: tile, matching: find.byType(Material)).first,
            );
            if (color == AppColor.haq) {
              if (index == 5 || index == 6) {
                expect(icon.color, const Color(0xFFCAA15D));
                expect(
                  material.color,
                  brightness == Brightness.dark
                      ? const Color(0xFF303A3B)
                      : const Color(0xFFF7F1E4),
                );
              }
            } else {
              expect(
                icon.color,
                accent.primary,
                reason: '${color.name}, shortcut $index',
              );
              expect(
                material.color,
                accent.soft,
                reason: '${color.name}, shortcut $index background',
              );
            }
          }
          if (color != AppColor.haq) {
            expect(
              tester.widget<Icon>(find.byIcon(Icons.calendar_month)).color,
              accent.primary,
            );
            for (final icon in tester.widgetList<Icon>(
              find.descendant(
                of: find.byType(PrayerCard),
                matching: find.byType(Icon),
              ),
            )) {
              expect(
                icon.color,
                accent.primary,
                reason: '${color.name}, prayer icon ${icon.icon}',
              );
            }
            expect(
              tester
                  .widget<Icon>(find.byIcon(Icons.wb_sunny_outlined).last)
                  .color,
              accent.primary,
            );
            expect(
              tester.widget<Icon>(find.byIcon(Icons.share_outlined)).color,
              accent.strong,
            );
          }
          if (color == AppColor.violet) {
            await prepareVisualAuditCapture(tester, boundary);
            await _capture(tester, boundary, 'home-icons-${brightness.name}');
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        appearance.dispose();
      },
    );

    testWidgets(
      'accent is shared by settings, Quran and religious content ${brightness.name}',
      (tester) async {
        final appearance = AppAppearance(prefs);
        await appearance.setMode(
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
        for (final color in AppColor.values) {
          await appearance.setColor(color);
          await tester.pumpWidget(
            _surface(
              appearance,
              Builder(
                builder: (context) {
                  final palette = AppPalette.of(context);
                  if (color != AppColor.haq) {
                    expect(qAccent(context), palette.tealHeading);
                    expect(rAccent(context), palette.tealHeading);
                    expect(
                      ReligiousColors(context).heading,
                      palette.tealHeading,
                    );
                    expect(qAccentFill(context), rAccentFill(context));
                    final foreground = palette.tealHeading.computeLuminance();
                    final background = palette.surface.computeLuminance();
                    final contrast = foreground > background
                        ? (foreground + .05) / (background + .05)
                        : (background + .05) / (foreground + .05);
                    expect(
                      contrast,
                      greaterThanOrEqualTo(4.5),
                      reason: color.name,
                    );
                    expect(
                      1.05 / (qAccentFill(context).computeLuminance() + .05),
                      greaterThanOrEqualTo(4.5),
                    );
                  }
                  return const Text('معاينة اللون');
                },
              ),
            ),
          );
        }
        await tester.pumpWidget(const SizedBox());
        appearance.dispose();
      },
    );

    testWidgets(
      'appearance controls work on narrow screens ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final appearance = AppAppearance(prefs);
        await appearance.setMode(
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
        await tester.pumpWidget(
          _surface(
            appearance,
            const SettingsDetailPage(kind: SettingKind.appearance),
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final color = find.byKey(const ValueKey('app-color-rose'));
        await tester.ensureVisible(color);
        await tester.pumpAndSettle();
        await tester.tap(color);
        await tester.pumpAndSettle();
        expect(appearance.color, AppColor.rose);
        final dropdown = find.byType(DropdownButtonFormField<AppFont>);
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('تجوال').last);
        await tester.pumpAndSettle();
        expect(appearance.font, AppFont.tajawal);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        appearance.dispose();
      },
    );

    testWidgets('appearance visual preview ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = DateTime(2026, 10, 29, 10);
      final appearance = AppAppearance(prefs, clock: () => now);
      await appearance.setMode(
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      );
      await appearance.setColor(AppColor.violet);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _surface(
            appearance,
            const SettingsDetailPage(kind: SettingKind.appearance),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await prepareVisualAuditCapture(tester, boundary);
      await _capture(tester, boundary, 'settings-${brightness.name}');
      await tester.ensureVisible(find.byType(DropdownButtonFormField<AppFont>));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'font-${brightness.name}');
      tester.view.physicalSize = const Size(390, 240);
      for (final day in [true, false]) {
        now = DateTime(2026, 10, 29, day ? 10 : 21);
        appearance.refreshTime();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: _surface(
              appearance,
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DhikrCard(onTap: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await prepareVisualAuditCapture(tester, boundary);
        await _capture(
          tester,
          boundary,
          '${day ? 'morning' : 'evening'}-${brightness.name}',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    });
  }
}

Widget _surface(AppAppearance appearance, Widget child, {double scale = 1}) =>
    AppearanceScope(
      controller: appearance,
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: Duration.zero,
          themeMode: appearance.mode,
          theme: ThemeData(
            fontFamily: appearance.font.family,
            extensions: [AppAccent(appearance.color, Brightness.light)],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: appearance.font.family,
            extensions: [AppAccent(appearance.color, Brightness.dark)],
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 1000),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(body: child),
            ),
          ),
        ),
      ),
    );

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/appearance-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
