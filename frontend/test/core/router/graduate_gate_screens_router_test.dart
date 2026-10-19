import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/view/graduate_application_screen.dart';
import 'package:campus_mate/graduate/view/graduate_waiting_screen.dart';
import 'package:campus_mate/graduate/view/verification_method_screen.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../../auth/model/fake_school_email_repository.dart';
import '../../auth/model/fake_verification_gate_repository.dart';
import '../../graduate/model/fake_graduate_verification_repository.dart';

/// 졸업생 관문 화면 4종(방법 고르기 · 신청 폼 · 대기 · 02) + 03 의 라우터 연결과 뒤로가기 규칙(계획서 Task 6 표
/// `app_router: gate_screens_*` [뒤로가기]). 화면이 스스로 [BackExitScope] 를 한 겹 두르고, 모두 go 로만 들어와 스택 깊이 1 이다.
void main() {
  late FakeGraduateVerificationRepository repository;
  late FakeVerificationGateRepository gateRepository;
  late GoRouter router;
  late ProviderContainer container;

  /// [gate] 를 서버가 내려 준 값으로 하고 라우터를 띄운다. 관문 값이 바뀌면 라우터가 화면을 옮긴다(main.dart 와 같은 연결).
  Future<void> pumpAt(WidgetTester tester, VerificationGate gate) async {
    repository = FakeGraduateVerificationRepository();
    gateRepository = FakeVerificationGateRepository()..nextResult = Success(gate);
    container = ProviderContainer(overrides: [
      graduateVerificationRepositoryProvider.overrideWithValue(repository),
      verificationGateRepositoryProvider.overrideWithValue(gateRepository),
      schoolEmailRepositoryProvider.overrideWithValue(FakeSchoolEmailRepository()),
      imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
    ]);
    addTearDown(container.dispose);
    final listenable = container.read(verificationGateListenableProvider);
    await listenable.refresh();
    router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: () => listenable.value,
      onboardingStep: () => OnboardingStep.basicInfo,
      refreshListenable: listenable,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 서버가 다음에 내려 줄 관문을 정하고, 화면이 하는 `refresh()` 대신 직접 한 번 묻는다.
  Future<void> serverMovesTo(WidgetTester tester, VerificationGate gate) async {
    gateRepository.nextResult = Success(gate);
    await container.read(verificationGateListenableProvider).refresh();
    await tester.pumpAndSettle();
  }

  const screens = <(VerificationGate, Type)>[
    (VerificationGate.needsVerificationMethod, VerificationMethodScreen),
    (VerificationGate.needsGraduateApplication, GraduateApplicationScreen),
    (VerificationGate.graduateReviewing, GraduateWaitingScreen),
    (VerificationGate.needsSchoolEmailChosen, SignUpScreen),
    (VerificationGate.needsSchoolEmail, SignUpScreen),
  ];

  group('관문 값이 화면을 고른다', () {
    for (final (gate, screen) in screens) {
      testWidgets('${gate.name} → $screen', (tester) async {
        await pumpAt(tester, gate);

        expect(find.byType(screen), findsOneWidget);
      });
    }
  });

  group('02 변형은 관문을 따라간다', () {
    testWidgets('02 에 머무는 동안 서버 플래그가 꺼져 관문이 needsSchoolEmail 로 바뀌면 뒤로 화살표가 사라진다', (tester) async {
      await pumpAt(tester, VerificationGate.needsSchoolEmailChosen);
      expect(find.byTooltip(onboardingBackLabel), findsOneWidget);

      await serverMovesTo(tester, VerificationGate.needsSchoolEmail);

      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byTooltip(onboardingBackLabel), findsNothing);
    });

    testWidgets('반대로 needsSchoolEmail → needsSchoolEmailChosen 이면 화살표가 생긴다', (tester) async {
      await pumpAt(tester, VerificationGate.needsSchoolEmail);
      expect(find.byTooltip(onboardingBackLabel), findsNothing);

      await serverMovesTo(tester, VerificationGate.needsSchoolEmailChosen);

      expect(find.byTooltip(onboardingBackLabel), findsOneWidget);
    });
  });

  group('gate_screens_have_exactly_one_back_exit_layer', () {
    for (final (gate, screen) in screens) {
      testWidgets('${gate.name}: BackExitScope 가 정확히 한 겹이다(두 겹이면 같은 뒤로에 종료 안내까지 뜬다)', (tester) async {
        await pumpAt(tester, gate);

        expect(find.byType(screen), findsOneWidget);
        expect(find.byType(BackExitScope), findsOneWidget);
      });
    }

    testWidgets('03 도 한 겹이다', (tester) async {
      await pumpAt(tester, VerificationGate.needsSchoolEmailChosen);

      router.go(AppRoutes.verifyCode, extra: UniversityEmail.tryParse('hong@snu.ac.kr'));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      expect(find.byType(BackExitScope), findsOneWidget);
    });
  });

  group('gate_screens_are_a_single_page_with_no_edge_swipe', () {
    int depth() => router.routerDelegate.currentConfiguration.matches.length;

    for (final (gate, screen) in screens) {
      testWidgets('${gate.name}: 뒤로 뺄 아래 화면이 없다(canPop false · 스택 1)', (tester) async {
        await pumpAt(tester, gate);

        expect(find.byType(screen), findsOneWidget);
        expect(router.canPop(), isFalse);
        expect(Navigator.of(tester.element(find.byType(screen))).canPop(), isFalse);
        expect(depth(), 1);
      });
    }

    testWidgets('03: canPop false · 스택 1', (tester) async {
      await pumpAt(tester, VerificationGate.needsSchoolEmailChosen);

      router.go(AppRoutes.verifyCode, extra: UniversityEmail.tryParse('hong@snu.ac.kr'));
      await tester.pumpAndSettle();

      expect(Navigator.of(tester.element(find.byType(VerifyCodeScreen))).canPop(), isFalse);
      expect(depth(), 1);
    });

    testWidgets('방법 고르기 → 학교 메일 → 화살표 왕복을 해도 스택은 1 이고 화면이 쌓이지 않는다', (tester) async {
      await pumpAt(tester, VerificationGate.needsVerificationMethod);

      // 학교 메일 카드 → [다음]: 서버가 방법을 저장하면 관문이 "학교 메일을 골랐다" 로 바뀐다.
      gateRepository.nextResult = const Success(VerificationGate.needsSchoolEmailChosen);
      await tester.tap(find.text('학교 메일로 인증'));
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byTooltip(onboardingBackLabel), findsOneWidget);
      expect(repository.chosen.single?.wire, 'school_email');
      expect(router.canPop(), isFalse);
      expect(depth(), 1);

      // 화살표 → 서버 값 비우기 → 관문이 "아직 안 골랐다" 로 돌아온다.
      gateRepository.nextResult = const Success(VerificationGate.needsVerificationMethod);
      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationMethodScreen), findsOneWidget);
      expect(repository.chosen.last, isNull);
      expect(router.canPop(), isFalse);
      expect(depth(), 1);

      // 졸업증명서 길도 같다.
      gateRepository.nextResult = const Success(VerificationGate.needsGraduateApplication);
      await tester.tap(find.text('졸업증명서로 인증'));
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.byType(GraduateApplicationScreen), findsOneWidget);
      expect(depth(), 1);

      gateRepository.nextResult = const Success(VerificationGate.needsVerificationMethod);
      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationMethodScreen), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(depth(), 1);
    });

    testWidgets('신청을 내면(관문이 심사 중으로) 화면이 대기 화면으로 바뀌고 스택은 1 이다', (tester) async {
      await pumpAt(tester, VerificationGate.needsGraduateApplication);

      await serverMovesTo(tester, VerificationGate.graduateReviewing);

      expect(find.byType(GraduateWaitingScreen), findsOneWidget);
      expect(depth(), 1);
    });
  });
}
