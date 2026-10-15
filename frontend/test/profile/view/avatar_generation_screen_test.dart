import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

      AnimatedOpacity reveal(WidgetTester tester) =>
          tester.widget<AnimatedOpacity>(find.descendant(of: find.byType(Image), matching: find.byType(AnimatedOpacity)));
      AnimatedScale grow(WidgetTester tester) =>
          tester.widget<AnimatedScale>(find.descendant(of: find.byType(Image), matching: find.byType(AnimatedScale)));

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
        expect(tester.getSize(find.byType(Image)), const Size(180, 180));
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
