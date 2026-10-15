import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';
import '../model/fake_avatar_repository.dart';
import '../model/fake_onboarding_repository.dart';

const _url = 'https://x.supabase.co/storage/v1/object/public/avatars/aa/avatar.png';

void main() {
  late FakeAvatarRepository repository;
  late FakeOnboardingRepository onboardingRepository;

  setUp(() {
    repository = FakeAvatarRepository();
    onboardingRepository = FakeOnboardingRepository();
  });

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        avatarRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AvatarGenerationScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('결과 화면은 다 찬 설문 막대를 그대로 둔다', (tester) async {
    // 05-12 계열은 6점 묶음이 아니다(pen) — 여기 오는 사람은 설문까지 이미 끝냈다.
    await pump(tester);

    expect(find.byType(ProgressDots), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first);
    expect(bar.value, 1.0);
  });

  testWidgets('완성 화면은 제목과 부제를 pen 문구 그대로 보여 준다', (tester) async {
    // 부제(pen `srOuh`)가 없으면 "다음" 이 무엇을 하는 버튼인지, 나중에 다시 만들 수 있는지를 아무도 모른다.
    repository.nextResult = const Success(AvatarReady(_url));

    await pump(tester);

    expect(find.text('아바타가 완성됐어요'), findsOneWidget);
    expect(
      find.text('마음에 들면 다음 단계로 넘어가요. 나중에 설정에서 다시 만들 수 있어요.'),
      findsOneWidget,
    );
  });

  // 사용자 요청 10-15 — 5b 아바타 공개 안내(pen `FXQlf`)를 따로 두지 않고 05-12c 에 설명 한 줄로 합친다. 비교 카드 둘은 넣지 않는다.
  group('매칭 전 공개 안내 한 줄', () {
    const notice = '매칭 전에는 AI가 그려준 아바타만 보여요. 상호 수락 후 신뢰 확인을 마치면 실제 사진이 공개돼요.';
    const lead = '마음에 들면 다음 단계로 넘어가요. 나중에 설정에서 다시 만들 수 있어요.';

    testWidgets('기존 부제 아래에 pen `FXQlf` 설명 문구가 붙고 버튼은 그 아래다', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));

      await pump(tester);

      expect(find.text('아바타가 완성됐어요'), findsOneWidget);
      expect(find.text(notice), findsOneWidget);
      expect(tester.getTopLeft(find.text(notice)).dy, greaterThan(tester.getBottomLeft(find.text(lead)).dy));
      expect(tester.getBottomLeft(find.text(notice)).dy, lessThan(tester.getTopLeft(find.text('다음')).dy));
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('작은 화면(360×640) · 글자 배율 $scale 에서도 넘치지 않고 "다음" 이 화면 안에 있다', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        repository.nextResult = const Success(AvatarReady(_url));

        await pump(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(notice), findsOneWidget);
        expect(tester.getBottomLeft(find.text('다음')).dy, lessThanOrEqualTo(640));
      });
    }
  });

  // 홈 레일이 실제 가입자 아바타를 흐리게 보여 준다(서버 `/home/people`, 10-15) — 완성 화면에서 미리 알린다.
  group('홈 레일 노출 안내 한 줄', () {
    const homeNotice = '흐리게 처리한 내 아바타가 홈 화면에서 다른 회원에게 보일 수 있어요';
    const notice = '매칭 전에는 AI가 그려준 아바타만 보여요. 상호 수락 후 신뢰 확인을 마치면 실제 사진이 공개돼요.';

    testWidgets('공개 안내 아래 8 에 14/400 #6A6A6A 가운데 정렬로 붙고, 버튼은 그 아래다', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));

      await pump(tester);
      // 기본 테스트 화면(800×600)에서는 버튼 위 스크롤 칸 아래쪽에 있다 — 끌어올려 본다.
      await tester.ensureVisible(find.text(homeNotice));
      await tester.pump();

      expect(find.text(homeNotice), findsOneWidget);
      expect(tester.getTopLeft(find.text(homeNotice)).dy - tester.getBottomLeft(find.text(notice)).dy, 8);
      expect(tester.getBottomLeft(find.text(homeNotice)).dy, lessThan(tester.getTopLeft(find.text('다음')).dy));
      final text = tester.widget<Text>(find.text(homeNotice));
      expect((text.style!.fontSize, text.style!.fontWeight, text.style!.color), (14, FontWeight.w400, const Color(0xFF6A6A6A)));
      expect(text.textAlign, TextAlign.center);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('작은 화면(360×640) · 글자 배율 $scale 에서도 넘치지 않고 "다음" 이 화면 안에 있다', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        repository.nextResult = const Success(AvatarReady(_url));

        await pump(tester);
        await tester.ensureVisible(find.text(homeNotice));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text(homeNotice), findsOneWidget);
        expect(tester.getBottomLeft(find.text('다음')).dy, lessThanOrEqualTo(640));
      });
    }
  });
  testWidgets('다음을 누르기 전에는 다음 단계를 묻지 않는다', (tester) async {
    // 받자마자 다음 단계를 물으면 라우터가 06-1 로 화면을 바꿔 버려서,
    // 애써 만든 아바타도 05-12d 의 보상 안내도 사람이 못 본다. 넘어가는 시점은 사람이 고른다.
    repository.nextResult = const Success(AvatarReady(_url));

    await pump(tester);

    expect(onboardingRepository.fetchCount, 0);

    await tester.tap(find.text('다음'));
    await tester.pump();

    expect(onboardingRepository.fetchCount, 1);
  });

  testWidgets('기본 아바타로 대신했어도 같은 완성 화면을 두고 시트로만 알린다', (tester) async {
    // pen 에 기본 아바타 전용 화면은 없다 — 05-12c 위에 05-12d 시트(`Q7VmU`)를 얹는다.
    repository.nextResult = const Success(AvatarFallback(_url, 10));

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('기본 아바타로 시작해요'), findsNothing);
    expect(find.text('아바타가 완성됐어요'), findsOneWidget);
    expect(find.text('기본 아바타로 대신했어요'), findsOneWidget);
    expect(
      find.text('서버 오류로 하트 10개 드렸어요. 설정 > 아바타 재생성 에서 다시 만들 수 있어요.'),
      findsOneWidget,
    );
    // 시트 버튼은 "확인" 하나다(pen 의 취소 버튼은 꺼져 있다).
    expect(find.text('확인'), findsOneWidget);
    expect(find.text('취소'), findsNothing);
  });

  group('완성 공개(DESIGN §7 standard — emphasis 는 하루 두 번 규칙에 들지 않아 쓰지 않는다)', () {
    void reduceMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    /// 만드는 중(첫 조회) → 다음 조회(5초 뒤)에 완성.
    Future<void> pumpUntilReady(WidgetTester tester) async {
      repository.statusResults.addAll([const Success(AvatarPending()), const Success(AvatarReady(_url))]);
      await pump(tester);
      expect(find.text('아바타를 만들고 있어요'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    }

    double opacityOf(WidgetTester tester, String text) =>
        tester.widget<FadeTransition>(find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).first).opacity.value;

    testWidgets('만드는 중 → 완성은 standard(220ms) 동안 겹쳐 바뀐다(바로 갈아끼우지 않는다)', (tester) async {
      await pumpUntilReady(tester);

      expect(find.text('아바타가 완성됐어요'), findsOneWidget);
      expect(find.text('아바타를 만들고 있어요'), findsOneWidget); // 아직 사라지는 중
      expect(opacityOf(tester, '아바타가 완성됐어요'), 0);

      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));
      expect(find.text('아바타를 만들고 있어요'), findsNothing);
      expect(opacityOf(tester, '아바타가 완성됐어요'), 1);
    });

    testWidgets('바뀌는 중에도 "다음" 을 누를 수 있다', (tester) async {
      await pumpUntilReady(tester);

      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(onboardingRepository.fetchCount, 1);
    });

    testWidgets('기기 "동작 줄이기" 면 바로 완성 화면이다', (tester) async {
      reduceMotion(tester);
      await pumpUntilReady(tester);
      await tester.pump();

      expect(find.text('아바타를 만들고 있어요'), findsNothing);
      expect(find.text('아바타가 완성됐어요'), findsOneWidget);
    });

    group('그림이 도착하면', () {
      late Completer<ImageInfo> arrived;

      /// 테스트 환경의 이미지 요청은 늘 400 이라, 같은 주소의 그림을 캐시에 먼저 넣어 두고 원하는 때 도착시킨다.
      /// 테스트 본문(가짜 시계 영역) 안에서 불러야 도착 처리가 pump 에 맞춰 돈다.
      void holdImage() {
        arrived = Completer<ImageInfo>();
        imageCache.putIfAbsent(const NetworkImage(_url), () => OneFrameImageStreamCompleter(arrived.future));
        addTearDown(imageCache.clear);
      }

      Future<void> arrive(WidgetTester tester) async {
        final image = await tester.runAsync(() => createTestImage(width: 4, height: 4));
        arrived.complete(ImageInfo(image: image!));
        await tester.pump();
      }

      // 만드는 중 화면의 마스코트(에셋 그림)가 겹쳐 사라지는 동안에도 아바타 그림(주소 그림)만 집는다.
      final avatarImage = find.byWidgetPredicate((widget) => widget is Image && widget.image is NetworkImage);
      AnimatedOpacity reveal(WidgetTester tester) =>
          tester.widget<AnimatedOpacity>(find.descendant(of: avatarImage, matching: find.byType(AnimatedOpacity)));
      AnimatedScale grow(WidgetTester tester) =>
          tester.widget<AnimatedScale>(find.descendant(of: avatarImage, matching: find.byType(AnimatedScale)));

      testWidgets('오기 전에는 투명 · 0.96 이고, 오면 standard 동안 1 · 1 로 나타난다', (tester) async {
        holdImage();
        repository.nextResult = const Success(AvatarReady(_url));
        await pump(tester);

        expect((reveal(tester).opacity, grow(tester).scale), (0, 0.96));
        await arrive(tester);

        expect((reveal(tester).opacity, grow(tester).scale), (1, 1));
        expect((reveal(tester).duration, reveal(tester).curve), (AppMotion.standard, AppMotion.standardCurve));
        expect((grow(tester).duration, grow(tester).curve), (AppMotion.standard, AppMotion.standardCurve));
        // 카드 · 그림 자리는 처음부터 180×180 — 커지는 것은 그림(transform)뿐이라 자리가 흔들리지 않는다.
        expect(tester.getSize(avatarImage), const Size(180, 180));
        await tester.pumpAndSettle();
      });

      testWidgets('기기 "동작 줄이기" 면 시간 0 으로 바로 다 보인다', (tester) async {
        reduceMotion(tester);
        holdImage();
        repository.nextResult = const Success(AvatarReady(_url));
        await pump(tester);
        await arrive(tester);

        expect((reveal(tester).opacity, grow(tester).scale), (1, 1));
        expect((reveal(tester).duration, grow(tester).duration), (Duration.zero, Duration.zero));
      });
    });
  });

  // pen 05-12 `OgHRY` · 05-12b `c7QuSm` 얼개(대장 전달 값 10-15) — 앱바 56 → 24 → 제목 → (8 → 부제) → 32 →
  // 상태 틀(328 · 최소 340 · 위 45 · 안 간격 12: 마스코트 220 → 스피너 28 / 힌트 13).
  group('만드는 중 · 실패 얼개(pen 05-12 · 05-12b)', () {
    const failedTitle = '아바타 생성에 실패했어요';
    const freeHint = '5번까지는 무료로 다시 시도할 수 있어요';
    // pen 원문(대장 전달 10-15, 유저플로우 사본도 같은 글). 05-12b 의 "시도해주세요" 는 원문 그대로 붙여 쓴다.
    const generatingSubtitle = '선택한 사진으로 아바타를 만드는 중이에요. 잠시만 기다려 주세요.';
    const failedSubtitle = '사진이 흐릿하거나 서버가 혼잡했을 수 있어요. 다른 사진으로 다시 시도해주세요.';
    const retryLabel = '다시 시도';
    final subtitleStyle = AppTypography.body.copyWith(color: AppColors.body);

    void penSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder mascot(String asset) => find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is AssetImage && (widget.image as AssetImage).assetName == asset,
        );

    testWidgets('05-12 — 제목 24/700 ink · 파란 목도리 마스코트 220 · 그 아래 12 에 스피너 28 muted · 버튼 없음', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarPending());
      await pump(tester);

      final title = find.text('아바타를 만들고 있어요');
      expect(tester.widget<Text>(title).style, AppTypography.headline.copyWith(color: AppColors.ink));
      expect(tester.getRect(title).top, 56 + 24);
      expect(tester.getRect(title).left, 16);

      final male = mascot('assets/images/mascot-male-waiting.png');
      expect(male, findsOneWidget);
      expect(tester.widget<Image>(male).fit, BoxFit.contain);
      final mascotRect = tester.getRect(male);
      expect(mascotRect.size, const Size(220, 220));
      expect(mascotRect.center.dx, 180);
      final subtitle = find.text(generatingSubtitle);
      expect(tester.widget<Text>(subtitle).style, subtitleStyle);
      expect(tester.getRect(subtitle).top, closeTo(tester.getRect(title).bottom + 8, 0.01));
      expect(tester.getRect(subtitle).width, lessThanOrEqualTo(328));
      expect(mascotRect.top, closeTo(tester.getRect(subtitle).bottom + 32 + 45, 0.01));

      final spinner = find.byType(CircularProgressIndicator);
      expect(tester.getRect(spinner).size, const Size(28, 28));
      expect(tester.getRect(spinner).top, mascotRect.bottom + 12);
      expect(tester.getRect(spinner).center.dx, 180);
      expect(tester.widget<CircularProgressIndicator>(spinner).color, AppColors.muted);
      expect(find.byType(AppButton), findsNothing);
      // 한 화면 마스코트 한 마리.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('05-12b — 제목 · 부제 · 분홍 목도리 마스코트 · 힌트 13/400 muted · 다시 시도 52 바닥 28 위', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarFailed());
      await pump(tester);
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      final title = find.text(failedTitle);
      expect(tester.widget<Text>(title).style, AppTypography.headline.copyWith(color: AppColors.ink));
      expect(tester.getRect(title).top, 56 + 24);
      final subtitle = find.text(failedSubtitle);
      expect(tester.widget<Text>(subtitle).style, subtitleStyle);
      expect(tester.getRect(subtitle).top, closeTo(tester.getRect(title).bottom + 8, 0.01));

      final sad = mascot('assets/images/mascot-female-sad.png');
      expect(sad, findsOneWidget);
      final mascotRect = tester.getRect(sad);
      expect(mascotRect.size, const Size(220, 220));
      expect(mascotRect.top, closeTo(tester.getRect(subtitle).bottom + 32 + 45, 0.01));

      final hint = find.text(freeHint);
      expect(tester.widget<Text>(hint).style, AppTypography.bodySmall.copyWith(fontSize: 13, color: AppColors.muted));
      expect(tester.getRect(hint).top, mascotRect.bottom + 12);
      expect(tester.getRect(hint).center.dx, 180);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final button = tester.getRect(find.byType(AppButton));
      expect(find.widgetWithText(AppButton, retryLabel), findsOneWidget);
      expect(button.height, 52);
      expect(button.width, 328);
      expect(button.bottom, 780 - 28);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('05-12b 다시 시도는 새 작업을 한 번 등록한다', (tester) async {
      repository.nextResult = const Success(AvatarFailed());
      await pump(tester);
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      await tester.tap(find.text(retryLabel));
      await tester.pump();

      expect(repository.generateCount, 1);
    });

    testWidgets('서버 문구가 있으면 힌트 자리에 같은 글꼴로 그 문구를 둔다', (tester) async {
      repository.nextResult = const Success(AvatarFailed());
      await pump(tester);
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));
      repository.nextResult = const FailureResult(ServerRejectedFailure('원본 사진을 다시 골라 주세요'));

      await tester.tap(find.text(retryLabel));
      await tester.pump();
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      final message = find.text('원본 사진을 다시 골라 주세요');
      expect(message, findsOneWidget);
      expect(tester.widget<Text>(message).style, AppTypography.bodySmall.copyWith(fontSize: 13, color: AppColors.muted));
      expect(find.text(freeHint), findsNothing);
    });

    // pen 은 부제가 328 폭에서 두 줄로 접혀 마스코트가 y249 다(56 + 24 + 32.4 + 8 + 25.6 × 2 + 32 + 45 = 248.6).
    // 시험 기본 글꼴(Ahem)은 글자 폭이 실제와 달라 줄 수를 못 믿는다 — 실제 글꼴 Pretendard 로 잰다.
    group('실제 글꼴(Pretendard)로 잰 pen 자리', () {
      setUpAll(loadPretendard);

      for (final (status, subtitleText, asset) in [
        (const AvatarPending() as AvatarGenerationOutcome, generatingSubtitle, 'assets/images/mascot-male-waiting.png'),
        (const AvatarFailed() as AvatarGenerationOutcome, failedSubtitle, 'assets/images/mascot-female-sad.png'),
      ]) {
        testWidgets('부제 두 줄(51.2) · 마스코트 y249 — ${status.runtimeType}', (tester) async {
          penSize(tester);
          repository.nextResult = Success(status);
          await pump(tester);
          await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

          // 두 줄 = 25.6 × 2. Pretendard 는 줄마다 26 으로 맞춰 그려 1 안쪽 차이가 난다(세 줄이면 77 이라 걸린다).
          expect(tester.getRect(find.text(subtitleText)).height, closeTo(16 * 1.6 * 2, 1));
          expect(tester.getRect(mascot(asset)).top, closeTo(249, 1));
        });
      }
    });

    for (final status in [const AvatarPending(), const AvatarFailed()]) {
      testWidgets('작은 화면(360×640) · 글자 2배에서도 넘치지 않는다 — ${status.runtimeType}', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        repository.nextResult = Success(status);

        await pump(tester);
        await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

        expect(tester.takeException(), isNull);
        if (status is AvatarFailed) {
          expect(tester.getRect(find.byType(AppButton)).bottom, lessThanOrEqualTo(640));
        }
      });
    }
  });

  testWidgets('그림을 못 불러와도 카드 크기를 지키고 예외 없이 그린다', (tester) async {
    // 테스트 환경의 이미지 요청은 늘 400 이다 — 운영에서 주소가 상했을 때와 같은 자리다.
    // 아바타는 서버에 이미 있다. 빈 카드로 두고 다음으로 갈 길만 남긴다(pen 에 대체 문구가 없다).
    repository.nextResult = const Success(AvatarReady(_url));

    await pump(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Image)), const Size(180, 180));
    final card = find.ancestor(of: find.byType(Image), matching: find.byType(Container)).first;
    expect(tester.getSize(card).height, 280);
    expect(find.text('다음'), findsOneWidget);
  });
}
