import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_appearance.dart';
import 'package:haq_app/main.dart';
import 'package:haq_app/features/community/presentation/community_page.dart';
import 'package:haq_app/features/quran/data/quran_audio_models.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/presentation/quran_audio_widgets.dart';
import 'package:haq_app/features/quran/presentation/quran_home_sections.dart';
import 'package:haq_app/features/sharing/share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository repository;
  late AppAppearance appearance;
  final exported = <String>[];
  const channel = MethodChannel('dev.fluttercommunity.plus/share');

  setUpAll(() {
    repository = QuranRepository.fromJson(
      jsonDecode(File('assets/quran/quran.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  test('publication sharing omits structured source metadata', () {
    expect(
      publicationShareText({
        'body': 'رسالة احتياطية',
        'content': {'text': 'نص المحتوى', 'source': 'مصدر المحتوى'},
      }),
      'نص المحتوى',
    );
    expect(publicationShareText({'body': 'رسالة حق'}), 'رسالة حق');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appearance = AppAppearance(await SharedPreferences.getInstance());
    exported.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          exported.add((call.arguments as Map)['text'] as String);
          return 'com.whatsapp';
        });
  });
  tearDown(() {
    appearance.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final entry in ['home', 'daily-verse', 'audio', 'app']) {
    testWidgets('$entry offers image or signed text before sharing', (
      tester,
    ) async {
      final child = switch (entry) {
        'home' => const DhikrCard(),
        'daily-verse' => QuranDailyVerse(
          repository: repository,
          onExplain: (_) {},
        ),
        'app' => const SocialMediaSection(),
        _ => Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareAudio(
              context,
              QuranAudioTrack(
                id: 'test',
                recitation: 'test',
                reciter: 'القارئ',
                title: 'سورة الفاتحة',
                surah: 1,
                url: 'https://example.com/001.mp3',
                version: '1',
                quality: 'test',
              ),
            ),
          ),
        ),
      };
      await pump(tester, child);
      await tester.tap(find.byIcon(Icons.share_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('مشاركة النص'), findsOneWidget);
      expect(find.text('مشاركة كصورة'), findsOneWidget);
      expect(exported, isEmpty);
      await tester.tap(find.text('مشاركة النص'));
      await tester.pumpAndSettle();
      expect(exported, hasLength(1));
      expect(exported.single, endsWith(ShareCardContent.signature));
      if (entry == 'daily-verse') {
        expect(exported.single, isNot(contains('Tanzil.net')));
        expect(exported.single, isNot(contains('سورة')));
      }
      if (entry == 'audio') {
        expect(exported.single, contains('https://example.com/001.mp3'));
        expect(exported.single, isNot(contains('القارئ')));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('image choice opens the branded editor without sharing text', (
    tester,
  ) async {
    await pump(tester, const SocialMediaSection());
    await tester.tap(find.text('شارك تطبيق حق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشاركة كصورة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ShareCardEditor), findsOneWidget);
    expect(
      tester
          .widget<ShareCardEditor>(find.byType(ShareCardEditor))
          .content
          .haqBranding,
      isTrue,
    );
    expect(exported, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
