import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/features/quran/presentation/quran_script.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['AmiriQuran', 'UthmanicHafs', 'ScheherazadeNew']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  test(
    'mark fallback preserves every Quran character and space for every reader font',
    () {
      final verses =
          (jsonDecode(File('assets/quran/quran.json').readAsStringSync())
                  as Map)['verses']
              as List;
      for (final family in [
        'AmiriQuran',
        'UthmanicHafs',
        'ScheherazadeNew',
        'NotoNaskhArabic',
        'Lateef',
      ]) {
        for (final verse in verses) {
          final text = verse['text'] as String;
          expect(
            quranScriptSpan(text, fontFamily: family).toPlainText(),
            text,
            reason: '$family ${verse['key']}',
          );
        }
      }
    },
  );
  test(
    'round zero stays a combining mark instead of a baseline circle in Hafs reading',
    () {
      for (final word in [
        'عَلِمُوا۟',
        'شَرَوْا۟',
        'ءَامَنُوا۟',
        'أُو۟لَـٰٓئِكَ',
      ]) {
        final fixed = TextPainter(
          text: TextSpan(
            style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 42),
            children: [quranScriptSpan(word, fontFamily: 'UthmanicHafs')],
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        final base = TextPainter(
          text: TextSpan(
            text: word.replaceAll('۟', ''),
            style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 42),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        expect(
          fixed.width,
          closeTo(base.width, .5),
          reason: 'The small zero must add no advancing baseline glyph: $word',
        );
        fixed.dispose();
        base.dispose();
      }
    },
  );
}
