import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import '../../billing/view/pretendard.dart';
import '../model/fake_school_email_repository.dart';
import '../model/fake_verification_gate_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 입력칸 아래 학교 메일 안내. 학교는 앱 업데이트 없이 DB 에 늘어나서(10-17 21곳 → 65곳) 학교 수를 쓰지 않는다(대장 결정 10-17).
const domainHint = '@snu.ac.kr · @yonsei.ac.kr · @korea.ac.kr 외 여러 곳';

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
      expect(find.text(domainHint), findsOneWidget);
      expect(find.text('인증 메일 받기'), findsOneWidget);
      // 묵시 동의 줄은 지웠다 — 동의는 로그인 뒤 02-c 에서 항목별로 받는다(사용자 결정 2026-09-29, pen KGo76 삭제).
      expect(find.textContaining('동의하게 돼요'), findsNothing);
    });

    testWidgets('학교 메일 안내에 학교 수(숫자)가 없다 — 학교가 늘어도 틀리지 않는다', (tester) async {
      await pumpScreen(tester);

      final hintRow = find.ancestor(of: find.byIcon(AppIcons.badgeCheck), matching: find.byType(Row)).first;
      final hint = tester.widget<Text>(find.descendant(of: hintRow, matching: find.byType(Text)));
      expect(hint.data, isNot(matches(RegExp(r'\d'))));
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

    // pen `TDM1r` padding [0,16] — school_info 상자(AppSpacing.md)와 같다.
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

  // 검토 권고(10-17): 03 에서 뒤로 왔다가 같은 메일로 다시 보내면 03 은 같은 family 인자라 옛 상태(떠난 시각 기준 타이머)를 다시 썼다 —
  // 들어가자마자 "메일 다시 받기" 가 켜져 서버 429 가 나거나, 오래 머물면 새 코드가 "만료" 로 보였다.
  group('02 → 03 → 뒤로 → 02 → 같은 메일로 다시 보내기', () {
    late DateTime now;
    late FakeSchoolEmailRepository repository;
    final hong = UniversityEmail.tryParse('hong@snu.ac.kr')!;

    Future<ProviderContainer> pumpFlow(WidgetTester tester) async {
      now = DateTime.now();
      repository = FakeSchoolEmailRepository();
      final container = ProviderContainer(
        overrides: [
          schoolEmailRepositoryProvider.overrideWithValue(repository),
          verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
          verifyCodeNowProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.login,
        routes: [
          GoRoute(path: AppRoutes.login, builder: (context, state) => const SignUpScreen()),
          GoRoute(
            path: AppRoutes.verifyCode,
            builder: (context, state) => VerifyCodeScreen(email: state.extra! as UniversityEmail),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      return container;
    }

    /// 02 에서 메일을 적고 보낸다 — 03 이 뜰 때까지(만료 타이머가 1초마다 다시 그려 pumpAndSettle 은 쓰지 않는다).
    Future<void> send(WidgetTester tester, String address) async {
      await tester.enterText(find.byType(TextField), address);
      await tester.pump();
      await tester.tap(find.text('인증 메일 받기'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> backTo02(WidgetTester tester) async {
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
    }

    testWidgets('02 에 60초 넘게 머문 뒤 같은 메일로 다시 보내면, 03 은 다시 보낸 때부터 센다 — 다시 받기는 잠기고 만료는 5분 뒤', (tester) async {
      final container = await pumpFlow(tester);
      await send(tester, 'hong@snu.ac.kr');
      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      await backTo02(tester);

      now = now.add(const Duration(minutes: 6)); // 다시 받기 쿨다운(60초) · 코드 유효 시간(5분)을 다 넘긴다
      final resentAt = now;
      await send(tester, 'hong@snu.ac.kr');

      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      final state = container.read(verifyCodeViewModelProvider(hong));
      expect(state.canResend(now), isFalse, reason: '들어오자마자 다시 받기가 켜지면 서버가 429 를 낸다');
      expect(state.resendAvailableAt, resentAt.add(const Duration(seconds: 60)));
      expect(state.codeExpiresAt, resentAt.add(codeLifetime));
      expect(state.isExpired(now), isFalse);
      expect(state.codeInput, isEmpty);
      expect(repository.requestedEmails, [hong, hong]);
    });

    testWidgets('다른 메일로 다시 보내면 그 메일의 03 이 뜨고 처음부터 센다(회귀 없음)', (tester) async {
      final container = await pumpFlow(tester);
      await send(tester, 'hong@snu.ac.kr');
      await backTo02(tester);

      now = now.add(const Duration(minutes: 2));
      final resentAt = now;
      await send(tester, 'kim@snu.ac.kr');

      expect(find.text('kim@snu.ac.kr 로 6자리 숫자를 보냈어요'), findsOneWidget);
      final state = container.read(verifyCodeViewModelProvider(UniversityEmail.tryParse('kim@snu.ac.kr')!));
      expect(state.resendAvailableAt, resentAt.add(const Duration(seconds: 60)));
      expect(state.codeExpiresAt, resentAt.add(codeLifetime));
    });
  });

  // 실제 글꼴로 잰다(시험 기본 Ahem 은 글자 폭이 실제와 다르다). 불러온 글꼴은 이 파일의 뒤 시험에도 남아 맨 끝에 둔다.
  group('학교 메일 안내 줄(실제 글꼴)', () {
    setUpAll(loadPretendard);

    void phone360(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    // 기준 설계 폭 360(DESIGN §11.1)에서 옛 문구처럼 한 줄이다 — 줄이 늘면 아래 칸이 밀린다.
    testWidgets('360 폭에서 안내는 한 줄이다', (tester) async {
      phone360(tester);
      await pumpScreen(tester);

      // 렌더 높이는 한 줄 17 · 두 줄 34 다(12 × 1.4 = 16.8 이 반올림된다) — 두 줄 높이보다 낮으면 한 줄이다.
      const caption = AppTypography.caption;
      expect(tester.getSize(find.text(domainHint)).height, lessThan(caption.fontSize! * caption.height! * 2));
    });

    testWidgets('360x640 · 글자 배율 2.0 에서 넘치지 않고 안내 전체가 보인다', (tester) async {
      phone360(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      // 안내 줄이 제 글자 높이보다 낮으면 잘린 것이다.
      final hint = tester.renderObject<RenderBox>(find.text(domainHint));
      expect(hint.size.height, greaterThanOrEqualTo(hint.getMinIntrinsicHeight(hint.size.width)));
      await tester.ensureVisible(find.text('인증 메일 받기'));
      await tester.pump();
      expect(find.text('인증 메일 받기').hitTestable(), findsOneWidget);
    });
  });
}
