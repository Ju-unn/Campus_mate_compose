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
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/bio_repository_provider.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:campus_mate/profile/model/onboarding_repository.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/profile/view/bio_screen.dart';
import 'package:campus_mate/profile/view/writing_example.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../referral/model/fake_referral_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_avatar_repository.dart';
import '../model/fake_bio_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';

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
Future<void> _pumpAtBio(
  WidgetTester tester,
  _StepRepository steps, {
  FakeBioRepository? bio,
  FakeAvatarRepository? avatar,
}) async {
  final container = ProviderContainer(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(steps),
      bioRepositoryProvider.overrideWithValue(bio ?? FakeBioRepository()),
      // 저장 뒤 아바타 확인 화면이 상태와 내 사진(리빌 왼쪽 칸)을 묻는다.
      avatarRepositoryProvider.overrideWithValue(
        avatar ?? (FakeAvatarRepository()..nextResult = const Success(AvatarReady('https://example.com/avatar.png'))),
      ),
      meRepositoryProvider.overrideWithValue(FakeMeRepository(const FailureResult(NetworkFailure()))),
      referralRepositoryProvider.overrideWithValue(FakeReferralRepository()),
      // 홈으로 잘못 튕겼을 때 홈이 오류 없이 그려져야 "홈에 갔다" 로 떨어진다.
      cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
      chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
      notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
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
  // 10-17 아바타 리빌 맨 끝: 06-3 뒤에는 20 이 아니라 아바타 확인(리빌 F84Alv · 만드는 중 · 실패)을 먼저 거친다.
  // Review Focus 2: 아바타가 이미 있으면 저장 순간 단계가 complete 가 된다 — 그래도 홈으로 튕기지 않고 리빌에 닿는다.
  testWidgets('06-3 을 저장하면 단계가 곧바로 complete 가 돼도 아바타 확인 화면에 도착한다', (tester) async {
    final steps = _StepRepository();
    await _pumpAtBio(tester, steps);
    expect(find.byType(BioScreen), findsOneWidget);

    steps.step = OnboardingStep.complete;
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarGenerationScreen), findsOneWidget);
    expect(find.byType(ReferralCodeScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('06-3 저장 때 아바타가 아직이면(서버 단계 avatar) 같은 아바타 확인 화면에 도착한다', (tester) async {
    final steps = _StepRepository();
    await _pumpAtBio(tester, steps, avatar: FakeAvatarRepository()..nextResult = const Success(AvatarPending()));

    steps.step = OnboardingStep.avatar;
    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AvatarGenerationScreen), findsOneWidget);
    expect(find.byType(ReferralCodeScreen), findsNothing);
  });

  testWidgets('단계 조회가 화면이 몇 번 그려진 뒤에 도착해도(느린 네트워크) 아바타 확인 화면에 도착한다', (tester) async {
    final steps = _StepRepository();
    await _pumpAtBio(tester, steps);

    steps
      ..step = OnboardingStep.complete
      ..hold = Completer<void>();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    steps.hold!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AvatarGenerationScreen), findsOneWidget);
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

  // 사용자 요청 10-15 — 입력칸 아래 예시 한 문장(문구는 사용자 승인 후보, 자리는 06-2a 와 같은 32).
  group('작성 예시 "이렇게 적어요"', () {
    testWidgets('입력칸 아래 32 에 예시 한 문장', (tester) async {
      await _pumpAtBio(tester, _StepRepository());

      final example = tester.widget<WritingExample>(find.byType(WritingExample));
      expect(example.sentences, ['같은 학교 친구들과 카페에서 공부하는 걸 좋아해요. 주말엔 운동하거나 영화 봐요.']);
      expect(tester.getTopLeft(find.byType(WritingExample)).dy - tester.getBottomLeft(find.byType(LabeledField)).dy, 32);
    });

    testWidgets('키보드가 올라와도 넘치지 않고 쓰는 칸이 키보드 위에 보인다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await _pumpAtBio(tester, _StepRepository());

      await tester.showKeyboard(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '주말엔 카페에서 책을 읽어요');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(EditableText)).bottom, lessThanOrEqualTo(780 - 300));
    });
  });

  // 2026-10-14 사용자 결정 "추천대로": 화면 상한 300자(서버는 1000 그대로), 엔터 줄은 칸 maxLines 와 같은 8줄.
  group('입력 상한', () {
    String fieldText(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).controller.text;

    testWidgets('300자(코드포인트)까지만 들어간다 — 카운터는 없다(pen yxga9)', (tester) async {
      await _pumpAtBio(tester, _StepRepository());

      await tester.enterText(find.byType(TextField), '가' * 301);
      await tester.pump();

      expect(fieldText(tester).runes.length, 300);
      expect(find.textContaining('/ 300'), findsNothing);
    });

    testWidgets('엔터 줄은 8줄까지 — 붙여 넣은 넘는 줄 바꿈은 공백이 된다', (tester) async {
      await _pumpAtBio(tester, _StepRepository());

      await tester.enterText(find.byType(TextField), '1\n2\n3\n4\n5\n6\n7\n8\n9');
      await tester.pump();

      expect(fieldText(tester), '1\n2\n3\n4\n5\n6\n7\n8 9');
    });
  });
}
