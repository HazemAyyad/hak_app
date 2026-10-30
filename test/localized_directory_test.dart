import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/core/localization/app_localization.dart';
import 'package:haq_app/navigation/more_page.dart';

void main() {
  testWidgets(
    'English directory searches localized titles regardless of case on a narrow screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final directory = Directory.systemTemp.createTempSync('haq-directory-');
      final localization = AppLocalization(preferences, directory: directory);
      final appearance = AppAppearance(preferences);
      addTearDown(() async {
        localization.dispose();
        appearance.dispose();
        directory.deleteSync(recursive: true);
      });
      await localization.select('en');
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalizationScope(
          controller: localization,
          child: AppearanceScope(
            controller: appearance,
            child: MaterialApp(
              home: Scaffold(body: MorePage(onFeature: (_) {})),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('more-search')),
        'QURAN',
      );
      await tester.pumpAndSettle();
      expect(find.text('The Holy Quran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
