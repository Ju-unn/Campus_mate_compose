import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import '../model/fake_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignUpScreen())),
    );
  }

  group('SignUpScreen', () {
    testWidgets('DESIGN.md 화면 02 확정 카피를 보여준다', (tester) async {
      await pumpScreen(tester);

      expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
      expect(find.text('학교 이메일 주소만 가입할 수 있어요.'), findsOneWidget);
      expect(find.text('인증이 끝나면 이메일은 어디에도 공개되지 않아요.'), findsOneWidget);
      expect(find.text('대학 이메일'), findsOneWidget);
      expect(find.text('@snu.ac.kr · @yonsei.ac.kr · @korea.ac.kr 외 17곳'), findsOneWidget);
      expect(find.text('인증 메일 받기'), findsOneWidget);
      expect(find.text('계속하면 이용약관과 개인정보처리방침에 동의하게 돼요.'), findsOneWidget);
    });

    testWidgets('앱바가 없다', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('이메일을 입력하기 전에는 CTA 가 비활성이다', (tester) async {
      await pumpScreen(tester);

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.enabled, isFalse);
    });

    testWidgets('형식이 올바른 이메일을 입력하면 CTA 가 활성화된다', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'hong@snu.ac.kr');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.enabled, isTrue);
    });

    testWidgets('제출 중에는 CTA 가 비활성이다', (tester) async {
      // 성공 결과를 쓰면 요청이 끝나자마자 인증코드 화면으로 이동을 시도하는데,
      // 이 테스트는 라우터 없는 MaterialApp 이라 그 이동이 죽는다. 로딩 중
      // 상태만 보면 되므로 실패 결과로 두고, 끝나면 pumpAndSettle 로 지연 타이머를 정리한다.
      final repository = FakeAuthRepository()..nextRequestOtpResult = const FailureResult(RateLimitedFailure());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: SignUpScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hong@snu.ac.kr');
      await tester.pump();

      await tester.tap(find.text('인증 메일 받기'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.enabled, isFalse);

      await tester.pumpAndSettle();
    });

    testWidgets('요청이 실패하면 에러 문구를 보여준다', (tester) async {
      final repository = FakeAuthRepository()..nextRequestOtpResult = const FailureResult(RateLimitedFailure());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: SignUpScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hong@snu.ac.kr');
      await tester.pump();

      await tester.tap(find.text('인증 메일 받기'));
      await tester.pumpAndSettle();

      expect(find.text('너무 많이 시도했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    });
  });
}
