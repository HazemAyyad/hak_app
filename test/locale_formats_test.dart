import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/core/localization/locale_formats.dart';

void main() {
  test(
    'Arabic, English and Russian plurals use language rules rather than fixed numeric branches',
    () {
      const ar = LocaleFormats('ar');
      expect([0, 1, 2, 3, 11, 100].map(ar.pluralCategory).toList(), [
        'zero',
        'one',
        'two',
        'few',
        'many',
        'other',
      ]);
      const en = LocaleFormats('en');
      expect([0, 1, 2].map(en.pluralCategory).toList(), [
        'other',
        'one',
        'other',
      ]);
      const ru = LocaleFormats('ru');
      expect([1, 2, 5, 21].map(ru.pluralCategory).toList(), [
        'one',
        'few',
        'many',
        'one',
      ]);
      expect(const LocaleFormats('zh-Hans').pluralCategory(1), 'other');
    },
  );

  test(
    'numbers follow the locale and dates preserve the Gregorian calendar',
    () {
      expect(const LocaleFormats('en').number(1234.5), '1,234.5');
      expect(const LocaleFormats('en').integer(1448), '1448');
      expect(const LocaleFormats('en').percent(2 / 3), '67%');
      expect(
        const LocaleFormats('en').clock24(DateTime(2026, 10, 31, 5, 7)),
        '05:07',
      );
      expect(const LocaleFormats('ar').number(1234.5), '1,234.5');
      expect(const LocaleFormats('de').number(1234.5), '1.234,5');
      expect(
        const LocaleFormats('en').gregorianDate(DateTime(2026, 10, 30)),
        'Oct 30, 2026',
      );
      expect(
        const LocaleFormats('zh-Hans').gregorianDate(DateTime(2026, 10, 30)),
        contains('2026'),
      );
      expect(const LocaleFormats('unregistered').number(1234.5), '1,234.5');
      expect(
        const LocaleFormats(
          'en',
        ).gregorianDateTime(DateTime(2026, 10, 30, 16, 5)),
        contains(RegExp(r'4:05\s+PM', unicode: true)),
      );
    },
  );
}
