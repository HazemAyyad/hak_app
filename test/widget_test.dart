import 'package:flutter_test/flutter_test.dart';
import 'package:haq_app/main.dart';

void main() {
  testWidgets('تعرض الصفحة الرئيسية الأساسية', (tester) async {
    await tester.pumpWidget(const HaqApp());

    expect(find.text('أحمد محمد'), findsOneWidget);
    expect(find.text('الصلاة القادمة'), findsOneWidget);
    expect(find.text('القرآن الكريم'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
