import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:campus_mate/profile/viewmodel/kakao_id_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../account/model/fake_account_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../model/fake_kakao_id_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  late FakeKakaoIdRepository kakao;
  late FakeOnboardingRepository onboarding;
  late FakeMeRepository me;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    kakao = FakeKakaoIdRepository();
    onboarding = FakeOnboardingRepository()..nextResult = const Success(OnboardingStep.kakaoId);
    me = FakeMeRepository(const Success(savedOnboardingProfile));
    final container = ProviderContainer(
      overrides: [
        kakaoIdRepositoryProvider.overrideWithValue(kakao),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        meRepositoryProvider.overrideWithValue(me),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(onboardingStepListenableProvider).refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KakaoIdScreen()),
      ),
    );
    return container;
  }

  OnboardingStep? step(ProviderContainer container) => container.read(onboardingStepListenableProvider).value;

  testWidgets('카카오톡 설정 화면 예시를 캡션과 함께 보여준다(pen W2tFQt)', (tester) async {
    await pump(tester);

    expect(find.text('카카오톡 설정 화면 예시'), findsOneWidget);
    expect(find.text('ID 검색 허용'), findsOneWidget);
    expect(find.text('카카오톡 > 설정 > 프로필 관리 > 카카오톡 ID 에서 켤 수 있어요'), findsOneWidget);
    // 16e-1 이 같은 그림을 복사 없이 쓴다 — 두 화면이 한 위젯을 본다.
    expect(find.byType(KakaoSettingExample), findsOneWidget);
    expect(find.descendant(of: find.byType(KakaoSettingExample), matching: find.byType(KakaoToggleImage)), findsOneWidget);
  });

  testWidgets('그림이라 탭에 반응하지 않고 한 문장으로 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final node = tester.getSemantics(find.text('ID 검색 허용'));
    expect(node.label, '카카오톡 설정 예시, ID 검색 허용 켜짐');
    // 켜고 끄는 건 카카오톡에서 한다 — 여기엔 누를 것이 없다.
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(find.byType(Switch), findsNothing);

    await tester.tap(find.byIcon(AppIcons.check), warnIfMissed: false);
    await tester.pump();

    expect(find.text('ID 검색 허용'), findsOneWidget);

    semantics.dispose();
  });

  group('뒤로가기', () {
    testWidgets('앱바 뒤로를 누르면 내 프로필을 읽은 뒤 04-1 로 간다', (tester) async {
      final container = await pump(tester);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pumpAndSettle();

      expect(step(container), OnboardingStep.basicInfo);
      expect(me.calls, 1);
    });

    // Review Focus 2: 저장이 끝난 뒤 stepSaved 가 엉뚱한 단계에서 한 칸 넘어가지 않게.
    testWidgets('저장 중 뒤로는 아무 일도 하지 않는다(화살표는 그대로 보인다)', (tester) async {
      final container = await pump(tester);
      kakao.hold = Completer<void>();
      await tester.enterText(find.byType(TextField), 'fox_rain');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(container.read(kakaoIdViewModelProvider).isSubmitting, isTrue, reason: '저장이 시작돼야 이 시험이 뜻이 있다');

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byTooltip(onboardingBackLabel), findsOneWidget);
      expect(step(container), OnboardingStep.kakaoId);
      expect(me.calls, 0);
      kakao.hold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('안드로이드 시스템 뒤로는 앱바 화살표와 같고 종료 안내는 뜨지 않는다', (tester) async {
      final container = await pump(tester);
      expect(find.byType(BackExitScope), findsOneWidget, reason: '라우터와 두 겹이면 같은 뒤로가기에 안내까지 뜬다');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(step(container), OnboardingStep.basicInfo);
      expect(find.text(backExitMessage), findsNothing);
    });
  });
}
