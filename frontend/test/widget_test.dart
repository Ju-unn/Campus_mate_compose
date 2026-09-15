import 'package:campus_mate/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('앱을 실행하면 로그인 화면으로 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CampusMateApp()));
    await tester.pumpAndSettle();

    expect(find.text('로그인'), findsOneWidget);
  });
}
