import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/features/prayer/data/place_catalog.dart';
import 'package:haq_app/features/prayer/data/prayer_controller.dart';
import 'package:haq_app/features/prayer/data/prayer_models.dart';
import 'package:haq_app/features/prayer/presentation/prayer_location_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Local transparent tiles exercise the real map/camera/tap projection without
// using a live tile service or pretending a fixture is geographic imagery.
class _Tiles extends TileProvider {
  @override
  ImageProvider getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrayerController controller;
  late AppAppearance appearance;
  late ValueNotifier<String> owner;
  PrayerLocation? result;
  final ps = PlaceCountry('PS', 'فلسطين', 'Palestine');
  final jo = PlaceCountry('JO', 'الأردن', 'Jordan');
  final catalog = PlaceCatalog(
    [ps, jo],
    [
      PlaceCity(
        id: 281133,
        name: 'غزة',
        english: 'Gaza',
        country: ps,
        latitude: 31.50161,
        longitude: 34.46672,
        zone: 'Asia/Gaza',
        population: 410000,
      ),
      PlaceCity(
        id: 285066,
        name: 'الخليل',
        english: 'Hebron',
        country: ps,
        latitude: 31.52935,
        longitude: 35.0938,
        zone: 'Asia/Hebron',
        population: 160470,
      ),
      PlaceCity(
        id: 282615,
        name: 'نابلس',
        english: 'Nablus',
        country: ps,
        latitude: 32.22111,
        longitude: 35.25444,
        zone: 'Asia/Hebron',
        population: 130326,
      ),
      PlaceCity(
        id: 250441,
        name: 'عمّان',
        english: 'Amman',
        country: jo,
        latitude: 31.95522,
        longitude: 35.94503,
        zone: 'Asia/Amman',
        population: 1275857,
      ),
    ],
  );
  final preview = GlobalKey();
  final previewScale = ValueNotifier<double>(1.5);
  setUpAll(() async {
    for (final (family, path) in [
      ('QuranUI', 'assets/fonts/Cairo.ttf'),
      (
        'MaterialIcons',
        'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    owner = ValueNotifier('guest');
    controller = PrayerController(
      prefs,
      scopeOf: () => owner.value,
      account: owner,
      autoTick: false,
    );
    appearance = AppAppearance(prefs);
    result = null;
  });
  tearDown(() {
    controller.dispose();
    appearance.dispose();
    owner.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool map = false,
    bool dark = false,
    double scale = 1.5,
    Future<String?> Function(double, double)? zoneAt,
    Future<PlaceCatalog> Function()? loader,
  }) async {
    previewScale.value = scale;
    tester.view.physicalSize = const Size(320, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: RepaintBoundary(
          key: preview,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'QuranUI',
              brightness: dark ? Brightness.dark : Brightness.light,
              colorSchemeSeed: const Color(0xFF2A8C82),
            ),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: previewScale,
              builder: (context, factor, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(factor)),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await Navigator.push<PrayerLocation>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrayerLocationPicker(
                            controller: controller,
                            showMap: map,
                            catalogLoader: loader ?? () async => catalog,
                            zoneAt: zoneAt ?? (_, _) async => 'Asia/Hebron',
                            tileProvider: _Tiles(),
                          ),
                        ),
                      );
                    },
                    child: const Text('فتح الاختيار'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح الاختيار'));
    await tester.pumpAndSettle();
  }

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('confirm-prayer-location')),
  );
  Future<void> query(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('prayer-place-query')),
      text,
    );
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final image =
          await (preview.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory('build/prayer-place-previews')
        ..createSync(recursive: true);
      File(
        '${dir.path}/$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'country then city search and confirmation at 320px / 150% ${dark ? 'dark' : 'light'}',
      (tester) async {
        await pump(tester, dark: dark);
        expect(confirm(tester).onPressed, isNull);
        expect(find.byType(FlutterMap), findsNothing);
        await query(tester, 'فلسطين');
        await tester.tap(find.text('دولة • عرض المدن'));
        await tester.pump();
        expect(find.byType(InputChip), findsOneWidget);
        expect(find.text('عمّان'), findsNothing);
        await query(tester, 'Hebron');
        await tester.tap(find.text('الخليل'));
        await tester.pumpAndSettle();
        expect(find.text('الخليل، فلسطين'), findsOneWidget);
        await capture(tester, 'search-${dark ? 'dark' : 'light'}');
        previewScale.value = 1;
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await capture(tester, 'search-default-${dark ? 'dark' : 'light'}');
        expect(confirm(tester).onPressed, isNotNull);
        expect(controller.config.location, isNull);
        await tester.tap(find.text('اعتماد هذا الموقع'));
        await tester.pumpAndSettle();
        expect(result?.latitude, 31.52935);
        expect(result?.zone, 'Asia/Hebron');
        expect(result?.label, 'الخليل، فلسطين');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real map taps retain projected pin and ignore older timezone replies; switching tabs keeps selection',
    (tester) async {
      final replies = <Completer<String?>>[];
      final points = <(double, double)>[];
      await pump(
        tester,
        map: true,
        zoneAt: (lat, lng) {
          points.add((lat, lng));
          final reply = Completer<String?>();
          replies.add(reply);
          return reply.future;
        },
      );
      expect(find.byType(MarkerLayer), findsNothing);
      final rect = tester.getRect(find.byType(FlutterMap));
      await tester.tapAt(rect.center);
      await tester.pump(const Duration(milliseconds: 300));
      expect(replies.length, 1);
      expect(confirm(tester).onPressed, isNull);
      await tester.tapAt(rect.center + const Offset(32, 45));
      await tester.pump(const Duration(milliseconds: 300));
      expect(replies.length, 2);
      replies.last.complete('Asia/Amman');
      await tester.pumpAndSettle();
      replies.first.complete('Europe/London');
      await tester.pumpAndSettle();
      final marker = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .single;
      expect(marker.point.latitude, points.last.$1);
      expect(marker.point.longitude, points.last.$2);
      await tester.tap(find.text('دولة أو مدينة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الخريطة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اعتماد هذا الموقع'));
      await tester.pumpAndSettle();
      expect(result?.zone, 'Asia/Amman');
      expect(result?.latitude, points.last.$1);
      expect(result?.longitude, points.last.$2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no land timezone refuses confirmation and lets user recover by searching',
    (tester) async {
      await pump(tester, map: true, zoneAt: (_, _) async => null);
      await tester.tapAt(tester.getRect(find.byType(FlutterMap)).center);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('لم نحدد منطقة زمنية'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
      await tester.tap(find.text('دولة أو مدينة'));
      await tester.pumpAndSettle();
      await query(tester, 'نابلس');
      await tester.tap(find.text('نابلس').last);
      await tester.pumpAndSettle();
      expect(confirm(tester).onPressed, isNotNull);
      expect(find.textContaining('لم نحدد منطقة زمنية'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog failure retries, unknown query is empty, and country filter can be cleared',
    (tester) async {
      var attempts = 0;
      await pump(
        tester,
        loader: () async {
          if (++attempts == 1) throw const FormatException('fixture');
          return catalog;
        },
      );
      expect(find.textContaining('تعذّر تحميل قائمة'), findsOneWidget);
      await tester.tap(find.text('إعادة تحميل المدن'));
      await tester.pumpAndSettle();
      await query(tester, 'xyz123');
      expect(find.textContaining('لا توجد نتائج'), findsOneWidget);
      await query(tester, 'الأردن');
      await tester.tap(find.text('دولة • عرض المدن'));
      await tester.pumpAndSettle();
      expect(find.text('غزة'), findsNothing);
      await tester.tap(find.byTooltip('جميع الدول'));
      await tester.pumpAndSettle();
      expect(find.text('غزة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account change closes picker and its source dialog; late point cannot leak into new account',
    (tester) async {
      final reply = Completer<String?>();
      await pump(tester, map: true, zoneAt: (_, _) => reply.future);
      await tester.tapAt(tester.getRect(find.byType(FlutterMap)).center);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('مصادر بيانات المواقع والخريطة'));
      await tester.pump(const Duration(milliseconds: 400));
      owner.value = 'account.42';
      await tester.pumpAndSettle();
      reply.complete('Asia/Hebron');
      await tester.pumpAndSettle();
      expect(find.byType(PrayerLocationPicker), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isNull);
      expect(controller.config.location, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
