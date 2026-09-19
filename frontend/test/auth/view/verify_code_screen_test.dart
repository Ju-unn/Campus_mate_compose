import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_auth_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  Future<void> pumpScreen(WidgetTester tester, {FakeAuthRepository? repository}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository ?? FakeAuthRepository())],
        child: MaterialApp(home: VerifyCodeScreen(email: email)),
      ),
    );
  }

  testWidgets('안내 문구와 재전송 버튼을 보여준다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('인증코드를 입력해 주세요'), findsOneWidget);
    expect(find.text('재전송'), findsOneWidget);
  });

  testWidgets('앱바가 없다', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('6자리를 모두 입력하기 전에는 CTA 가 비활성이다', (tester) async {
    await pumpScreen(tester);

    // 재전송도 ElevatedButton 이라 .first 대신 라벨로 확인 버튼을 특정한다.
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '확인'));
    expect(button.enabled, isFalse);
  });

  testWidgets('검증에 실패하면 에러 문구를 보여준다', (tester) async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(UnknownFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('알 수 없는 오류가 발생했습니다'), findsOneWidget);
  });
}
