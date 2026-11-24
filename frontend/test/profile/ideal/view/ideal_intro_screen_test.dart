import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/profile/ideal/view/ideal_intro_screen.dart';
import 'package:campus_mate/profile/ideal/viewmodel/ideal_intro_view_model.dart';
import 'package:campus_mate/profile/onboarding/model/data/onboarding_step.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/viewmodel/onboarding_back_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../onboarding/model/repository/fake_onboarding_repository.dart';

// pen 25-B 이상형 들어가기 3장(lP32p · t66q5i · gzKOH) — 값은 UI값표_CT5Lq_11-24 §15.
const _line1 = '지금까지는 나에 대해 알려 주셨어요';
const _line2 = '이제 내가 좋아하는 사람에 대해';
const _line3 = '알려 주세요';
const _caption = '화면을 누르면 바로 넘어가요';

/// 줄 위의 투명도를 모두 곱한 값 — 화면에 보이는 진하기.
double _opacityOf(WidgetTester tester, String text) {
  var opacity = 1.0;
  for (final element in find.ancestor(of: find.text(text), matching: find.byType(Opacity)).evaluate()) {
    opacity *= (element.widget as Opacity).opacity;
  }
  for (final element in find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).evaluate()) {
    opacity *= (element.widget as FadeTransition).opacity.value;
  }
  return opacity;
}

(double, double, double) _lineOpacities(WidgetTester tester) =>
    (_opacityOf(tester, _line1), _opacityOf(tester, _line2), _opacityOf(tester, _line3));

void main() {
  late int doneCount;
  late int backCount;

  Future<void> pumpIntro(WidgetTester tester, {bool reduceMotion = false, bool screenReader = false}) async {
    doneCount = 0;
    backCount = 0;
    if (reduceMotion || screenReader) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduceMotion, accessibleNavigation: screenReader);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IdealIntroScreen(onDone: () => doneCount++, onBack: () => backCount++),
      ),
    );
  }

  group('IdealIntroScreen', () {
    testWidgets('글 3줄 · 캡션 · 마스코트 120 · 앱바 점 3개가 pen 값이다', (tester) async {
      tester.view.physicalSize = const Size(360, 780); // pen 화면 크기
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpIntro(tester);
      await tester.pump(const Duration(seconds: 2));

      final line1 = tester.widget<Text>(find.text(_line1)).style!;
      expect((line1.fontSize, line1.fontWeight, line1.height, line1.color), (16, FontWeight.w400, 1.6, AppColors.muted));
      for (final headline in [_line2, _line3]) {
        final style = tester.widget<Text>(find.text(headline)).style!;
        expect((style.fontSize, style.fontWeight, style.height, style.color), (24, FontWeight.w700, 1.35, AppColors.ink));
      }
      for (final line in [_line1, _line2, _line3]) {
        expect(tester.widget<Text>(find.text(line)).textAlign, TextAlign.center);
      }
      final caption = tester.widget<Text>(find.text(_caption)).style!;
      expect((caption.fontSize, caption.fontWeight, caption.color), (12, FontWeight.w400, AppColors.muted));

      // 그림 교체 대기: pen i5Ud2(mascot-female-reward)는 앱에 없어 같은 토끼 기본 그림을 임시로 쓴다.
      final mascot = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage && (widget.image as AssetImage).assetName == 'assets/images/mascot-female.webp',
      );
      expect(tester.getSize(mascot), const Size(120, 120));

      final appBar = tester.widget<OnboardingAppBar>(find.byType(OnboardingAppBar));
      expect((appBar.current, appBar.total, appBar.isBar), (0, 3, false));
      // pen Body gap 32: 마스코트 아래 32 에 첫 줄.
      expect(tester.getTopLeft(find.text(_line1)).dy - tester.getBottomLeft(mascot).dy, 32);
      // pen Footer padding 아래 32.
      expect(780 - tester.getBottomLeft(find.text(_caption)).dy, 32);
    });

    testWidgets('줄 투명도가 장마다 (1,0,0) → (0.5,1,0) → (0.5,1,1) 이다', (tester) async {
      await pumpIntro(tester);

      await tester.pump(const Duration(milliseconds: 500));
      expect(_lineOpacities(tester), (1.0, 0.0, 0.0));

      // 첫 줄 흐려짐은 700ms 타이머 뒤 프레임에서 시작한다 — 한 번에 건너뛰면 그 프레임이 없어 따로 민다.
      await tester.pump(const Duration(milliseconds: 300)); // 800ms
      await tester.pump(const Duration(milliseconds: 500)); // 1300ms
      expect(_lineOpacities(tester), (0.5, 1.0, 0.0));

      await tester.pump(const Duration(milliseconds: 700)); // 2000ms
      expect(_lineOpacities(tester), (0.5, 1.0, 1.0));
    });

    testWidgets('줄은 아래에서 올라오며 나타난다', (tester) async {
      await pumpIntro(tester);
      await tester.pump(const Duration(milliseconds: 1450)); // 셋째 줄이 막 움직이기 시작했다
      final rising = tester.getTopLeft(find.text(_line3)).dy;

      await tester.pump(const Duration(milliseconds: 600));
      expect(rising, greaterThan(tester.getTopLeft(find.text(_line3)).dy));
    });

    testWidgets('다 나오고 1.2초 뒤 혼자 넘어간다', (tester) async {
      await pumpIntro(tester);

      // 줄 간격 700 × 2 + 셋째 줄 올라오기 400 + 기다림 1200 = 3000ms
      await tester.pump(const Duration(milliseconds: 2990));
      expect(doneCount, 0);

      await tester.pump(const Duration(milliseconds: 10));
      expect(doneCount, 1);
    });

    testWidgets('화면 읽기가 켜져 있으면 세 줄을 한 번에 보이고, 몇 초가 지나도 넘어가지 않고 누를 때만 넘어간다', (tester) async {
      await pumpIntro(tester, screenReader: true);
      await tester.pump();

      expect(_lineOpacities(tester), (0.5, 1.0, 1.0));
      await tester.pump(const Duration(seconds: 10));
      expect(doneCount, 0);

      await tester.tapAt(const Offset(180, 400));
      await tester.pump();
      expect(doneCount, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('화면 아무 데나 누르면 바로 넘어가고, 타이머가 다시 넘기지 않는다', (tester) async {
      await pumpIntro(tester);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tapAt(const Offset(40, 300));
      await tester.pump();
      expect(doneCount, 1);

      await tester.tap(find.text(_caption));
      await tester.pump(const Duration(seconds: 5));
      expect(doneCount, 1);
    });

    testWidgets('타이머로 넘어간 뒤 눌러도 한 번만 넘어간다', (tester) async {
      await pumpIntro(tester);
      await tester.pump(const Duration(milliseconds: 3100));
      expect(doneCount, 1);

      await tester.tapAt(const Offset(180, 400));
      await tester.pump();
      expect(doneCount, 1);
    });

    testWidgets('동작 줄이기면 세 줄을 한 번에 보이고 1.5초 뒤 넘어간다', (tester) async {
      await pumpIntro(tester, reduceMotion: true);
      await tester.pump();

      expect(_lineOpacities(tester), (0.5, 1.0, 1.0));

      await tester.pump(const Duration(milliseconds: 1400));
      expect(doneCount, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(doneCount, 1);
      await tester.pumpAndSettle(); // 움직이는 것이 없어 바로 끝난다
    });

    testWidgets('움직임이 끝나면 pumpAndSettle 이 끝난다', (tester) async {
      await pumpIntro(tester);

      await tester.pumpAndSettle();

      expect(_lineOpacities(tester), (0.5, 1.0, 1.0));
    });

    testWidgets('화면을 떠나면 타이머가 취소된다', (tester) async {
      await pumpIntro(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));

      expect(doneCount, 0);
    });

    testWidgets('앱바 뒤로는 넘어가지 않고 뒤로 함수를 부른다', (tester) async {
      await pumpIntro(tester);

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pump();

      expect((backCount, doneCount), (1, 0));
    });

    for (final textScale in [1.0, 1.5]) {
      testWidgets('폭 320 · 글자 $textScale배에서 넘치지 않는다', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpIntro(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final line in [_line1, _line2, _line3, _caption]) {
          final rect = tester.getRect(find.text(line));
          expect(rect.left, greaterThanOrEqualTo(24), reason: line);
          expect(rect.right, lessThanOrEqualTo(320 - 24), reason: line);
        }
      });
    }
  });

  group('IdealIntroGate', () {
    late FakeOnboardingRepository repository;
    late ProviderContainer container;

    Future<void> pumpGate(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: IdealIntroGate(child: _CountingTarget()),
          ),
        ),
      );
    }

    setUp(() {
      repository = FakeOnboardingRepository()..nextResult = const Success(OnboardingStep.idealConditions);
      _CountingBackViewModel.calls = 0;
      container = ProviderContainer(
        overrides: [
          onboardingRepositoryProvider.overrideWithValue(repository),
          onboardingBackViewModelProvider.overrideWith(_CountingBackViewModel.new),
        ],
      );
      addTearDown(container.dispose);
    });

    // 넘어가는 220ms 동안 들어가기와 06-1 의 뒤로 받는 곳이 둘 다 살아 있으면 시스템 뒤로 한 번에 둘 다 불린다.
    testWidgets('넘어가는 중의 시스템 뒤로는 06-1 쪽 한 번만 불린다', (tester) async {
      _CountingTarget.backs = 0;
      await container.read(onboardingStepListenableProvider).refresh();
      await pumpGate(tester);
      await tester.pump(const Duration(milliseconds: 3000)); // 타이머가 넘겼다 — 06-1 이 페이드인 중이다
      await tester.pump(const Duration(milliseconds: 50));

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect((_CountingBackViewModel.calls, _CountingTarget.backs), (0, 1));
      await tester.pumpAndSettle();
    });

    testWidgets('가입 길이면 들어가기를 먼저 보이고, 누르면 06-1 이다', (tester) async {
      await container.read(onboardingStepListenableProvider).refresh();
      await pumpGate(tester);
      await tester.pump();

      expect(find.byType(IdealIntroScreen), findsOneWidget);
      expect(find.text('06-1'), findsNothing);
      expect(container.read(idealIntroViewModelProvider), isTrue, reason: '한 번 보인 것을 기억한다');

      await tester.tapAt(const Offset(180, 400));
      await tester.pumpAndSettle();

      expect(find.byType(IdealIntroScreen), findsNothing);
      expect(find.text('06-1'), findsOneWidget);
    });

    testWidgets('넘어가는 220ms 동안의 누름은 06-1 에 닿지 않고, 다 바뀐 뒤에는 닿는다', (tester) async {
      _CountingTarget.taps = 0;
      await container.read(onboardingStepListenableProvider).refresh();
      await pumpGate(tester);
      await tester.pump(const Duration(milliseconds: 3000)); // 타이머가 넘겼다 — 06-1 이 페이드인 중이다
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tapAt(const Offset(180, 400));
      await tester.pump();
      expect(_CountingTarget.taps, 0);

      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(180, 400));
      await tester.pump();
      expect(_CountingTarget.taps, 1);
    });

    testWidgets('이미 봤으면 06-1 을 바로 보인다', (tester) async {
      await container.read(onboardingStepListenableProvider).refresh();
      container.read(idealIntroViewModelProvider.notifier).markSeen();

      await pumpGate(tester);

      expect(find.byType(IdealIntroScreen), findsNothing);
      expect(find.text('06-1'), findsOneWidget);
    });

    testWidgets('06-2 에서 돌아온 06-1 이면 06-1 을 바로 보인다', (tester) async {
      await revisit(container, repository, server: OnboardingStep.idealTraits, visiting: OnboardingStep.idealConditions);

      await pumpGate(tester);

      expect(find.byType(IdealIntroScreen), findsNothing);
      expect(find.text('06-1'), findsOneWidget);
    });
  });
}

/// 06-1 자리 — 눌린 횟수를 센다(넘어가는 도중의 누름이 06-1 칩에 닿는지 본다).
class _CountingTarget extends StatelessWidget {
  const _CountingTarget();

  static int taps = 0;

  /// 06-1 이 자기 [BackExitScope] 로 받은 뒤로 횟수 — 실제 06-1 화면처럼 뒤로 받는 곳을 하나 둔다.
  static int backs = 0;

  @override
  Widget build(BuildContext context) {
    return BackExitScope(
      onBack: () => backs++,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++, child: const Center(child: Text('06-1'))),
    );
  }
}

/// 들어가기의 뒤로(설문으로 한 단계)가 불린 횟수만 센다.
class _CountingBackViewModel extends OnboardingBackViewModel {
  static int calls = 0;

  @override
  Future<void> goBack() async => calls++;
}
