import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/app_refresh.dart';

void main() {
  testWidgets(
    'short pages refresh once, use their own data source, and retain a single indicator',
    (tester) async {
      var general = 0, local = 0;
      final finished = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: AppRefreshHost(
            onRefresh: () async {
              general++;
            },
            child: Scaffold(
              body: AppRefreshRegion(
                onRefresh: () {
                  local++;
                  return finished.future;
                },
                child: ListView(children: const [Text('Short page')]),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(local, 1);
      expect(general, 0);
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pump();
      expect(local, 1);
      finished.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary pages use the shared refresh; horizontal readers do not trigger it',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppRefreshHost(
            onRefresh: () async {
              calls++;
            },
            child: Scaffold(body: ListView(children: const [Text('Settings')])),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: AppRefreshHost(
            onRefresh: () async {
              calls++;
            },
            child: Scaffold(
              body: PageView(
                children: const [Text('Page one'), Text('Page two')],
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
