import 'dart:async';

import 'package:campus_mate/account/model/repository/account_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/me/model/repository/me_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:campus_mate/profile/onboarding/model/repository/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/view/kakao_id_screen.dart';
import 'package:campus_mate/profile/onboarding/viewmodel/kakao_id_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../account/model/repository/fake_account_repository.dart';
import '../../../me/model/repository/fake_me_repository.dart';
import '../model/repository/fake_kakao_id_repository.dart';
import '../model/repository/fake_onboarding_repository.dart';

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
        child: const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: KakaoIdScreen()),
      ),
    );
    return container;
  }

  OnboardingStep? step(ProviderContainer container) => container.read(onboardingStepListenableProvider).value;

  testWidgets('카카오톡 설정 화면 예시를 캡션과 함께 보여준다(pen W2tFQt)', (tester) async {
    await pump(tester);

    expect(find.text('카카오톡 설정 화면 예시'), findsOneWidget);
    expect(find.text('ID 검색 허용'), findsOneWidget);
    expect(find.text('카카오톡 홈 > 전체 설정 > 관리 > 카카오톡 ID에서 켤 수 있어요'), findsOneWidget);
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

  // 할 일 3 · pen gprMl(I-4) · 대장 판정(11-24): 오류 줄과 안내 줄은 따로, 안내 줄은 언제나 보인다.
  group('입력 중 미리 검사', () {
    testWidgets('안쪽에 공백이 있으면 칸 아래 오류가 뜨고 다음이 꺼지며, 안내 줄은 그대로 보인다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'my id');
      // 손을 멈춘 뒤까지 본다 — 300ms 디바운스 타이머가 시험 끝에 남지 않게.
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('공백 없이 적어 주세요'), findsOneWidget);
      expect(find.descendant(of: find.byType(LabeledField), matching: find.byIcon(AppIcons.circleAlert)), findsOneWidget);
      expect(find.text('설정 > 계정에서 언제든 바꿀 수 있어요'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '다음')).enabled, isFalse);
    });

    testWidgets('공백 아닌 이유로 거절될 값은 손을 멈춘 뒤 칸 아래 입력 오류가 뜨고 다음이 꺼진다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(find.text('입력한 값을 다시 확인해 주세요'), findsNothing);

      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('입력한 값을 다시 확인해 주세요'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '다음')).enabled, isFalse);
    });

    // pen gprMl Z2l77 gap 20: 칸 DJ0C2 · 안내 줄 qPWyr · 꼭 확인 카드 flTKJ 사이가 모두 20.
    for (final input in ['my_id', 'my id']) {
      testWidgets('안내 줄은 칸 · 오류 줄 아래 20 에 있다($input)', (tester) async {
        await pump(tester);
        await tester.enterText(find.byType(TextField), input);
        await tester.pump(const Duration(milliseconds: 350));

        final fieldBottom = tester.getBottomLeft(find.byType(LabeledField)).dy;
        final helperTop = tester.getTopLeft(find.text('설정 > 계정에서 언제든 바꿀 수 있어요')).dy;
        expect(helperTop - fieldBottom, 20);

        final helperBottom = tester.getBottomLeft(find.text('설정 > 계정에서 언제든 바꿀 수 있어요')).dy;
        expect(tester.getTopLeft(find.byType(NoticeCard)).dy - helperBottom, 20);
      });
    }

    testWidgets('공백이 아니면 오류 없이 안내 줄만 보이고 다음이 켜진다', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'my_id');
      // 손을 멈춘 뒤까지 본다 — 300ms 디바운스 타이머가 시험 끝에 남지 않게.
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('공백 없이 적어 주세요'), findsNothing);
      expect(find.text('설정 > 계정에서 언제든 바꿀 수 있어요'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '다음')).enabled, isTrue);
    });
  });

  group('뒤로가기', () {
    testWidgets('앱바 뒤로를 누르면 내 프로필을 읽은 뒤 04-1 로 간다', (tester) async {
      final container = await pump(tester);

      await tester.tap(find.byTooltip('뒤로'));
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

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byTooltip('뒤로'), findsOneWidget);
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
      expect(find.text('한 번 더 누르면 종료돼요'), findsNothing);
    });
  });
}
