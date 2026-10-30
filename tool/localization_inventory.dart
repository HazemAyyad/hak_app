import 'dart:convert';
import 'dart:io';

/// Lexical candidates for editorial classification; never rewrites scripture.
void main() {
  final records = <Map<String, dynamic>>[];
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') &&
                !file.path.endsWith('bundled_localization.dart'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final text = file.readAsStringSync();
    for (var i = 0; i < text.length; i++) {
      final quote = text[i];
      if (quote != "'" && quote != '"') continue;
      final start = i;
      final triple = text.startsWith(quote * 3, i);
      final delimiter = quote * (triple ? 3 : 1);
      final raw = i > 0 && text[i - 1] == 'r';
      i += delimiter.length;
      final begin = i;
      while (i < text.length && !text.startsWith(delimiter, i)) {
        if (!raw && text[i] == r'\') {
          i += 2;
        } else {
          i++;
        }
      }
      if (i >= text.length) break;
      final value = text.substring(begin, i);
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(value)) {
        records.add({
          'file': file.path.replaceAll('\\', '/'),
          'line': '\n'.allMatches(text.substring(0, start)).length + 1,
          'candidate': value,
          'classification': 'needs_ui_or_content_review',
        });
      }
      i += delimiter.length - 1;
    }
  }
  final counts = <String, int>{};
  for (final record in records) {
    counts.update(
      record['file'] as String,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  Directory('build').createSync(recursive: true);
  File(
    'build/localization-inventory.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
  final report = StringBuffer('# حصر مرشحات الترجمة — 30 أكتوبر 2026\n\n')
    ..writeln(
      'حصر نصي أولي لـ${records.length} مقطع يحتوي العربية في ${counts.length} ملفًا. يشمل مرشحات واجهة ونصوص محتوى ورسائل؛ ليس عدد مفاتيح واجهة معتمدة ولا إثبات اكتمال الترجمة. الأصل الديني يصنف ويحمى قبل أي استخراج. التفاصيل المحلية في `build/localization-inventory.json`.\n',
    )
    ..writeln('| الملف | المرشحات التي تحتاج تصنيفًا |\n| --- | --- |');
  for (final entry in counts.entries) {
    report.writeln('| `${entry.key}` | ${entry.value} |');
  }
  File('docs/localization-inventory.md').writeAsStringSync(report.toString());
  stdout.writeln(
    '${records.length} candidates in ${counts.length} files; no application source or bundled content was rewritten.',
  );
}
