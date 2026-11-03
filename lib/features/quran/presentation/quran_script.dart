import 'package:flutter/painting.dart';

final _scriptWords = RegExp(r'\s+|\S+');

/// Preserve the source text while avoiding unsupported Quran mark rendering.
/// A whole word uses the covering face so Arabic joining stays intact.
TextSpan quranScriptSpan(String text, {required String fontFamily}) {
  final needsRoundZero =
      fontFamily == 'UthmanicHafs' && text.contains('\u06df');
  final needsFatha = fontFamily == 'AmiriQuran' && text.contains('\u065e');
  if (!needsRoundZero && !needsFatha) return TextSpan(text: text);

  return TextSpan(
    children: [
      for (final match in _scriptWords.allMatches(text))
        TextSpan(text: match[0], style: _coveringStyle(match[0]!, fontFamily)),
    ],
  );
}

TextStyle? _coveringStyle(String word, String family) {
  // This bundled Hafs face draws U+06DF as a full dotted circle at the baseline.
  // Amiri renders the same source mark as a small ring above its actual letter.
  if (family == 'UthmanicHafs' && word.contains('\u06df')) {
    return TextStyle(
      fontFamily: word.contains('\u065e') ? 'ScheherazadeNew' : 'AmiriQuran',
    );
  }
  if (family == 'AmiriQuran' && word.contains('\u065e')) {
    return TextStyle(
      fontFamily: word.contains('\u06df') ? 'ScheherazadeNew' : 'UthmanicHafs',
    );
  }
  return null;
}
