import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

/// Optional, separate 100% text captures. Ordinary accessibility tests keep
/// their original viewport and scale; no production settings are changed.
const visualAudit = bool.fromEnvironment('HAQ_VISUAL_AUDIT');
Size visualSize(Size original) =>
    visualAudit ? const Size(390, 1000) : original;
double visualScale(double original) => visualAudit ? 1 : original;
String visualPath(String original) => visualAudit
    ? 'build/visual-audit/current/${original.substring('build/'.length)}'
    : original;

/// Widget tests use Ahem for unspecified text, unlike the app's Arabic theme.
/// Replace that test-only fallback for normal visual exports, not app code.
Future<void> loadVisualAuditFonts() async {
  if (!visualAudit) return;
  for (final family in ['Ahem', 'Roboto', 'Arial']) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  }
  await (FontLoader('Tajawal')
        ..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Tajawal-Bold.ttf')))
      .load();
}

Future<void> prepareVisualAuditCapture(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  if (!visualAudit) return;
  final context = boundaryKey.currentContext!;
  final providers = find
      .descendant(of: find.byKey(boundaryKey), matching: find.byType(Image))
      .evaluate()
      .map((element) => (element.widget as Image).image)
      .whereType<AssetImage>()
      .toSet();
  await tester.runAsync(() async {
    await Future.wait(
      providers.map((provider) => precacheImage(provider, context)),
    );
  });
  await tester.pump();
}

/// Capture the rest of a scrollable surface at 100%, then restore its offset.
/// This never runs in the ordinary accessibility/behavior suite.
Future<void> captureAuditContinuation(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) async {
  if (!visualAudit) return;
  final surface = find.byKey(boundaryKey);
  final scrollables = find.descendant(
    of: surface,
    matching: find.byType(Scrollable),
  );
  ScrollPosition? position;
  for (final element in scrollables.evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.axis == Axis.vertical &&
        state.position.maxScrollExtent > 100) {
      position = state.position;
      break;
    }
  }
  if (position == null) return;
  final original = position.pixels;
  try {
    final step = position.viewportDimension * .8;
    for (var page = 1; page <= 4; page++) {
      final next = (original + step * page).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (next <= position.pixels + 1) break;
      position.jumpTo(next);
      await tester.pump();
      await prepareVisualAuditCapture(tester, boundaryKey);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(path.replaceFirst('.png', '-scroll-$page.png'));
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  } finally {
    position.jumpTo(original.clamp(0.0, position.maxScrollExtent));
    await tester.pump();
  }
}
