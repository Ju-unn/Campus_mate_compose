import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import '../model/fake_school_email_repository.dart';
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
      // 묵시 동의 줄은 지웠다 — 동의는 로그인 뒤 02-c 에서 항목별로 받는다(사용자 결정 2026-09-29, pen KGo76 삭제).
      expect(find.textContaining('동의하게 돼요'), findsNothing);
    });

    testWidgets('앱바가 없다', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(AppBar), findsNothing);
    });

    // 디자인 공통 PR 뒤 창별_할일(온보딩): 입력 상자 모서리 input 12 · 테두리 hairline, placeholder muted.
    testWidgets('이메일 입력 상자는 모서리 12 · 테두리 hairline, placeholder 는 muted 다', (tester) async {
      await pumpScreen(tester);

      final field = find.byType(TextField);
      final box = tester
          .widget<Container>(find.ancestor(of: field, matching: find.byType(Container)).first)
          .decoration! as BoxDecoration;
      expect(box.borderRadius, BorderRadius.circular(AppRadius.input));
      expect(box.border, Border.all(color: AppColors.hairline));
      expect(tester.widget<TextField>(field).decoration!.hintStyle!.color, AppColors.muted);
    });

    // pen `TDM1r` padding [0,16] — school_info · student_verification 상자(AppSpacing.md)와 같다.
    testWidgets('이메일 상자 안쪽 가로 여백은 16 이다', (tester) async {
      await pumpScreen(tester);

      final box = find.ancestor(of: find.byType(TextField), matching: find.byType(Container)).first;
      expect(tester.widget<Container>(box).padding, const EdgeInsets.symmetric(horizontal: 16));
    });

    // DESIGN §11.2 — 폰 크기에서 글자 배율 2.0 이어도 화면이 넘치지 않는다(넘치면 스크롤된다).
    testWidgets('폰 크기 · 글자 배율 2.0 에서 화면이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('인증 메일 받기'));
      await tester.pump();
      expect(find.text('인증 메일 받기').hitTestable(), findsOneWidget);
    });

    // 52 는 최소값이다 — 글자 배율 1.75 부터 고정 52 면 한 줄이 잘린다(LabeledField 와 같이 minHeight).
    testWidgets('글자 배율 2.0 에서 이메일 상자가 늘어나 글자가 잘리지 않는다', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester);

      // 글자칸이 제 한 줄 높이보다 낮으면 잘린 것이다.
      final text = tester.renderObject<RenderBox>(find.byType(EditableText));
      expect(text.size.height, greaterThanOrEqualTo(text.getMinIntrinsicHeight(text.size.width)));
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
      final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(RateLimitedFailure());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [schoolEmailRepositoryProvider.overrideWithValue(repository)],
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
      final repository = FakeSchoolEmailRepository()..nextRequestCodeResult = const FailureResult(RateLimitedFailure());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [schoolEmailRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: SignUpScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hong@snu.ac.kr');
      await tester.pump();

      await tester.tap(find.text('인증 메일 받기'));
      await tester.pumpAndSettle();

      expect(find.text('너무 많이 시도했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    });

    testWidgets('등록되지 않은 학교 메일이면 서버 문구를 입력칸 아래에 보여준다(팝업 없음)', (tester) async {
      final repository = FakeSchoolEmailRepository()
        ..nextRequestCodeResult = const FailureResult(SignUpRejectedFailure('등록되지 않은 학교 메일이에요'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [schoolEmailRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: SignUpScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hong@unknown.ac.kr');
      await tester.pump();

      await tester.tap(find.text('인증 메일 받기'));
      await tester.pumpAndSettle();

      expect(find.text('등록되지 않은 학교 메일이에요'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  // 학교 메일은 약관 동의(02-c) 다음 관문이다 — 앞 화면으로 돌아갈 곳이 없고, 소셜로 잘못 들어온 사람의 탈출구가 로그아웃이다.
  group('관문 화면(동의 다음)', () {
    testWidgets('뒤로가기 화살표가 없다', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('맨 아래 CTA 밑에 02-c 와 같은 로그아웃 글자 버튼이 있다(48 · 14/600 muted)', (tester) async {
      await pumpScreen(tester);

      final logout = find.widgetWithText(InkWell, '로그아웃');
      expect(logout, findsOneWidget);
      final cta = tester.getRect(find.byType(ElevatedButton));
      expect(tester.getRect(logout).top, cta.bottom + 4);
      expect(tester.getRect(logout).height, 48);
      final label = tester.widget<Text>(find.text('로그아웃'));
      expect(label.style!.color, AppColors.muted);
      expect(label.style!.fontSize, 14);
      expect(label.style!.fontWeight, FontWeight.w600);
    });

    // 디자인 값: 02 아래 여백 16(지시문 16). 맨 아래 줄(로그아웃)이 화면 아래에서 16 위에 끝난다.
    testWidgets('맨 아래 여백은 16 이다', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScreen(tester);

      expect(tester.getRect(find.widgetWithText(InkWell, '로그아웃')).bottom, 844 - 16);
    });

    testWidgets('로그아웃은 16g 시트로 한 번 더 묻고, 확인하면 로그아웃을 한 번 부른다', (tester) async {
      var signOutCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [signOutProvider.overrideWithValue(() async => signOutCalls++)],
          child: const MaterialApp(home: SignUpScreen()),
        ),
      );

      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(find.text('로그아웃할까요?'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(SafetyConfirmSheet), matching: find.text('로그아웃')));
      await tester.pumpAndSettle();

      expect(signOutCalls, 1);
    });
  });

  // 탈퇴한 계정이 로그아웃된 뒤의 알림(pen V12leV · Toast 인스턴스 EuJqq, 대장 결정 3).
  group('로그인 화면 알림', () {
    // LoginNotice 는 전역 값이다 — 테스트끼리 값이 새지 않게 매번 비운다(대장 요구).
    tearDown(LoginNotice.take);

    testWidgets('login screen shows the posted notice above the CTA and hides it after 3s', (tester) async {
      LoginNotice.post('탈퇴한 계정이에요');
      await pumpScreen(tester);

      final toast = find.byType(AppToast);
      expect(toast, findsOneWidget);
      expect(find.descendant(of: toast, matching: find.text('탈퇴한 계정이에요')), findsOneWidget);
      expect(find.descendant(of: toast, matching: find.byIcon(AppIcons.alertTriangle)), findsOneWidget);
      // CTA 바로 위 12(pen KJnpw), 가로 가운데(Row cAPme).
      final cta = tester.getRect(find.byType(ElevatedButton));
      expect(tester.getRect(toast).bottom + 12, cta.top);
      expect(tester.getRect(toast).center.dx, cta.center.dx);

      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('login screen shows no toast without a notice', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('한 번 보인 알림은 다시 들어와도 뜨지 않는다', (tester) async {
      LoginNotice.post('탈퇴한 계정이에요');
      await pumpScreen(tester);
      await tester.pumpWidget(const SizedBox());

      await pumpScreen(tester);

      expect(find.byType(AppToast), findsNothing);
    });
  });
}
