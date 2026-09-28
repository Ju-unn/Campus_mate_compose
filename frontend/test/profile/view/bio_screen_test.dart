import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/bio_screen.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../referral/model/fake_referral_repository.dart';
import '../model/fake_bio_repository.dart';

/// 서버 next-step 을 흉내 낸다. [hold] 가 있으면 그것이 끝날 때까지 답을 미룬다(느린 네트워크).
class _StepRepository implements OnboardingRepository {
  OnboardingStep step = OnboardingStep.bio;
  Completer<void>? hold;

  @override
  Future<Result<OnboardingStep>> fetchNextStep() async {
    await hold?.future;
    return Success(step);
  }
}

/// main.dart 와 같은 모양으로 실제 라우터(redirect · refreshListenable)를 세우고 06-3 에서 시작한다.
Future<void> _pumpAtBio(WidgetTester tester, _StepRepository steps, {FakeBioRepository? bio}) async {
  final container = ProviderContainer(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(steps),
      bioRepositoryProvider.overrideWithValue(bio ?? FakeBioRepository()),
      referralRepositoryProvider.overrideWithValue(FakeReferralRepository()),
      // 홈으로 잘못 튕겼을 때 홈이 오류 없이 그려져야 "홈에 갔다" 로 떨어진다.
      cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
      chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
    ],
  );
  addTearDown(container.dispose);
  final stepCache = container.read(onboardingStepListenableProvider);
  await stepCache.refresh();
  final router = AppRouter.create(
    isAuthenticated: () => true,
    verificationGate: () => VerificationGate.complete,
    onboardingStep: () => stepCache.value,
    refreshListenable: stepCache,
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

void main() {
  // Review Focus 5: 06-3 저장 뒤 단계 캐시가 complete 로 바뀌며 홈으로 튕기면 20 이 한 번도 안 보인다.
  testWidgets('06-3 을 저장하면 단계가 곧바로 complete 가 돼도 20 추천 코드 화면에 도착한다', (tester) async {
    final steps = _StepRepository();
    await _pumpAtBio(tester, steps);
    expect(find.byType(BioScreen), findsOneWidget);

    steps.step = OnboardingStep.complete;
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(find.byType(ReferralCodeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('단계 조회가 화면이 몇 번 그려진 뒤에 도착해도(느린 네트워크) 20 에 도착한다', (tester) async {
    final steps = _StepRepository();
    await _pumpAtBio(tester, steps);

    steps
      ..step = OnboardingStep.complete
      ..hold = Completer<void>();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    steps.hold!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ReferralCodeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('저장이 실패하면 06-3 에 머문다', (tester) async {
    final steps = _StepRepository();
    await _pumpAtBio(
      tester,
      steps,
      bio: FakeBioRepository()..nextSubmitResult = const FailureResult(NetworkFailure()),
    );

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(find.byType(BioScreen), findsOneWidget);
    expect(find.byType(ReferralCodeScreen), findsNothing);
  });
}
