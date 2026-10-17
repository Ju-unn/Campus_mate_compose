import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/referral_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../billing/view/pretendard.dart';
import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';
import '../../referral/model/fake_referral_repository.dart';
import '../model/fake_avatar_repository.dart';
import '../model/fake_onboarding_repository.dart';

const _url = 'https://x.supabase.co/storage/v1/object/public/avatars/aa/avatar.png';

/// 아바타 원본으로 고른 내 사진(서명 주소, 지어낸 값). 대표 사진(0번)은 원본이 아니다 — 고른 장을 집는지 본다.
const _sourcePhotoUrl = 'https://x.supabase.co/storage/v1/object/sign/profile-photos/aa/1.jpg?token=t';
const _me = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: _url,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: '안녕하세요',
  photos: [
    MyPhoto(id: 'p0', url: 'https://x.supabase.co/storage/v1/object/sign/profile-photos/aa/0.jpg?token=t', isAvatarSource: false),
    MyPhoto(id: 'p1', url: _sourcePhotoUrl, isAvatarSource: true),
  ],
);

// pen F84Alv "아바타 리빌" 문구(대장 전달 pen 값 10-17).
// 제목은 줄바꿈 문자로 두 줄 고정(대장 결정 10-17 — pen 도 같은 줄바꿈). 312 폭에 한 줄로 들어가도 접는다.
const _revealTitle = '짜잔, 매칭 전에는\n이렇게 보여요';
const _realLabel = '나만 보는 실제 사진';
const _avatarLabel = '상대에게 보이는 모습';
const _revealBody = '매칭 전에는 AI가 그려준 아바타만 보여요. 상호 수락 후 신뢰 확인을 마치면 실제 사진이 공개돼요.';
const _confirmLabel = '확인했어요';
const _lockedPhotoSemantics = '나만 보는 실제 사진, 가려져 있어요';
const _homeNotice = '내 아바타가 홈 화면에서 다른 회원에게 보일 수 있어요';

/// 20(추천 코드) 자리 — 화면 시험은 이동만 본다(실제 20 은 아래 '실제 라우터' 묶음).
const _referralStub = '20 추천 코드';

void main() {
  late FakeAvatarRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late FakeMeRepository me;

  setUp(() {
    repository = FakeAvatarRepository();
    onboardingRepository = FakeOnboardingRepository();
    me = FakeMeRepository(const Success(_me));
  });

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        avatarRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
        meRepositoryProvider.overrideWithValue(me),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.onboardingAvatar,
      routes: [
        GoRoute(path: AppRoutes.onboardingAvatar, builder: (context, state) => const AvatarGenerationScreen()),
        GoRoute(path: AppRoutes.onboardingReferral, builder: (context, state) => const Text(_referralStub)),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void penSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  Finder networkImage(String url) =>
      find.byWidgetPredicate((widget) => widget is Image && widget.image is NetworkImage && (widget.image as NetworkImage).url == url);

  /// 비교 칸 둘(140×175 · 모서리 24). 왼쪽(실사진)이 먼저다.
  final cells = find.byWidgetPredicate(
    (widget) => widget is ClipRRect && widget.borderRadius == BorderRadius.circular(24),
  );

  // 가입 맨 끝(06-3 뒤 · 20 앞)이라 앱바 · 진행 막대 · 뒤로가 없다(F84Alv · OgHRY · euW4T, 대장 전달 10-17).
  // 시스템 뒤로는 라우터의 종료 안내(BackExitScope)가 맡는다 — app_router_test.
  group('세 상태 모두 앱바 · 진행 막대 · 뒤로 없음', () {
    for (final status in [const AvatarPending(), const AvatarFailed(), const AvatarReady(_url)]) {
      testWidgets('${status.runtimeType}', (tester) async {
        repository.nextResult = Success(status);
        await pump(tester);
        await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

        expect(find.byType(OnboardingAppBar), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byTooltip(onboardingBackLabel), findsNothing);
      });
    }
  });

  group('완성 — 리빌(pen F84Alv)', () {
    testWidgets('제목 · 두 칸 라벨 · 설명 · 확인했어요를 pen 문구 그대로 보여 주고 옛 05-12c 문구는 없다', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);

      expect(find.text(_revealTitle), findsOneWidget);
      expect(find.text(_realLabel), findsOneWidget);
      expect(find.text(_avatarLabel), findsOneWidget);
      expect(find.text(_revealBody), findsOneWidget);
      expect(find.widgetWithText(AppButton, _confirmLabel), findsOneWidget);
      expect(find.text('아바타가 완성됐어요'), findsNothing);
      expect(find.text('마음에 들면 다음 단계로 넘어가요. 나중에 설정에서 다시 만들 수 있어요.'), findsNothing);
      expect(find.text('다음'), findsNothing);
    });

    testWidgets('글꼴 — 제목 24/700 ink 가운데 · 라벨 12/600 muted · 12/700 ink · 설명 14/500 body 1.5 가운데', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);

      final title = tester.widget<Text>(find.text(_revealTitle));
      expect(title.style, AppTypography.headline.copyWith(color: AppColors.ink));
      expect(title.textAlign, TextAlign.center);
      final real = tester.widget<Text>(find.text(_realLabel)).style!;
      expect((real.fontSize, real.fontWeight, real.color), (12, FontWeight.w600, AppColors.muted));
      final avatar = tester.widget<Text>(find.text(_avatarLabel)).style!;
      expect((avatar.fontSize, avatar.fontWeight, avatar.color), (12, FontWeight.w700, AppColors.ink));
      final body = tester.widget<Text>(find.text(_revealBody));
      expect((body.style!.fontSize, body.style!.fontWeight, body.style!.color, body.style!.height), (14, FontWeight.w500, AppColors.body, 1.5));
      expect(body.textAlign, TextAlign.center);
    });

    testWidgets('자리(360×780) — 위 64 · 폭 312 · 간격 24 · 칸 x32/x188 140×175 · 라벨 8 아래 · 확인했어요 24,696 312×52', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);

      final title = tester.getRect(find.text(_revealTitle));
      expect((title.top, title.left, title.width), (64, 24, 312));

      expect(cells, findsNWidgets(2));
      final real = tester.getRect(cells.at(0));
      final avatar = tester.getRect(cells.at(1));
      expect(real, const Rect.fromLTWH(32, 0, 140, 175).shift(Offset(0, real.top)));
      expect(avatar, const Rect.fromLTWH(188, 0, 140, 175).shift(Offset(0, real.top)));
      expect(real.top, closeTo(title.bottom + 24, 0.01));
      // 칸 아래 8 에 라벨, 칸 가운데 정렬. 비교 줄 199 = 칸 175 + 8 + 라벨 16.
      final realLabel = tester.getRect(find.text(_realLabel));
      final avatarLabel = tester.getRect(find.text(_avatarLabel));
      expect(realLabel.top, real.bottom + 8);
      expect(avatarLabel.top, avatar.bottom + 8);
      expect((realLabel.center.dx, avatarLabel.center.dx), (real.center.dx, avatar.center.dx));
      expect(realLabel.bottom - real.top, 199);

      final body = tester.getRect(find.text(_revealBody));
      expect((body.top, body.left, body.width), (realLabel.bottom + 24, 24, 312));

      expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(24, 696, 312, 52));
    });

    testWidgets('왼쪽 칸 — 아바타로 고른 내 사진을 cover · 흐림 14 로 그리고 흰 자물쇠 28 · 가림 라벨을 단다', (tester) async {
      final semantics = tester.ensureSemantics();
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);
      // 만드는 중 표시에서 겹쳐 바뀌는 동안(투명도 0 부터)은 화면 읽기에 아직 안 잡힌다 — 다 바뀐 뒤 본다.
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      final photo = networkImage(_sourcePhotoUrl);
      expect(photo, findsOneWidget);
      expect(tester.widget<Image>(photo).fit, BoxFit.cover);
      final blur = tester.widget<ImageFiltered>(find.ancestor(of: photo, matching: find.byType(ImageFiltered)));
      expect(blur.imageFilter, ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.clamp));
      expect(find.ancestor(of: photo, matching: cells), findsOneWidget);

      final lock = find.byIcon(AppIcons.lock);
      expect(lock, findsOneWidget);
      final icon = tester.widget<Icon>(lock);
      expect((icon.size, icon.color), (28.0, AppColors.onInk));
      expect(tester.getCenter(lock), tester.getCenter(cells.at(0)));
      // 잠금 덮개(140×175, 모서리 24 로 잘림) — 검정 25% 를 깔아 흰 자물쇠가 밝은 사진 위에서도 보이게(대장 전달 pen 값 10-17).
      final scrim = find.descendant(
        of: cells.at(0),
        matching: find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == const Color(0x40000000)),
      );
      expect(scrim, findsOneWidget);
      expect(tester.getRect(scrim), tester.getRect(cells.at(0)));

      expect(find.bySemanticsLabel(_lockedPhotoSemantics), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('오른쪽 칸 — 서버가 준 아바타 주소 그대로 cover · 흐림 없음 · 분홍 테두리 2', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);
      await tester.pump();

      final avatar = networkImage(_url);
      expect(avatar, findsOneWidget);
      expect(tester.widget<Image>(avatar).fit, BoxFit.cover);
      expect(find.ancestor(of: avatar, matching: find.byType(ImageFiltered)), findsNothing);
      expect(find.ancestor(of: avatar, matching: cells), findsOneWidget);
      final border = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration == BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
      );
      expect(border, findsOneWidget);
      expect(tester.getRect(border), tester.getRect(cells.at(1)));
    });

    testWidgets('사진 · 아바타를 못 받아도 칸 140×175 를 지키고 예외 없이 그린다', (tester) async {
      // 테스트 환경의 이미지 요청은 늘 400 이다 — 운영에서 서명 주소가 상했을 때와 같은 자리다.
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final cell in cells.evaluate()) {
        expect(cell.size, const Size(140, 175));
      }
      expect(find.byIcon(AppIcons.lock), findsOneWidget);
      expect(find.text(_confirmLabel), findsOneWidget);
    });

    testWidgets('내 프로필을 못 받으면 왼쪽은 같은 크기 빈 칸(자물쇠 · 가림 라벨은 그대로)', (tester) async {
      final semantics = tester.ensureSemantics();
      me = FakeMeRepository(const FailureResult(NetworkFailure()));
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      expect(networkImage(_sourcePhotoUrl), findsNothing);
      expect(tester.getSize(cells.at(0)), const Size(140, 175));
      expect(find.byIcon(AppIcons.lock), findsOneWidget);
      expect(find.bySemanticsLabel(_lockedPhotoSemantics), findsOneWidget);
      semantics.dispose();
    });

    // 홈 레일이 실제 가입자 아바타를 블러 없이 보여 준다(서버 `/home/people`, PR #550 · 블러 제거 10-17) — 개인정보 안내라 리빌 설명 아래에 남긴다.
    // pen F84Alv 에는 아직 없다(결정 G2 — pen 수정 필요).
    // pen 에 방금 추가된 값(대장 전달 10-17): 설명 바로 아래 8 · 14/400 #6A6A6A · 가운데 · 폭 312 · 줄높이 1.5.
    testWidgets('홈 노출 안내 한 줄은 설명 아래 8 에 14/400 muted 가운데 · 폭 312 · 줄높이 1.5 로 남고 버튼 자리는 그대로다', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);

      final notice = find.text(_homeNotice);
      expect(notice, findsOneWidget);
      final rect = tester.getRect(notice);
      expect(rect.top - tester.getRect(find.text(_revealBody)).bottom, 8);
      expect((rect.left, rect.width), (24, 312));
      expect(rect.bottom, lessThan(tester.getRect(find.byType(AppButton)).top));
      final text = tester.widget<Text>(notice);
      expect(
        (text.style!.fontSize, text.style!.fontWeight, text.style!.color, text.style!.height),
        (14, FontWeight.w400, AppColors.muted, 1.5),
      );
      expect(text.textAlign, TextAlign.center);
      expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(24, 696, 312, 52));
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('작은 화면(360×640) · 글자 배율 $scale 에서도 넘치지 않고 확인했어요가 화면 안에 있다', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        repository.nextResult = const Success(AvatarReady(_url));

        await pump(tester);
        await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

        expect(tester.takeException(), isNull);
        expect(tester.getBottomLeft(find.text(_confirmLabel)).dy, lessThanOrEqualTo(640));
        // 글자가 커져도 칸은 140×175 그대로다 — 라벨만 줄이 늘어난다.
        expect(tester.getSize(cells.at(0)), const Size(140, 175));
      });
    }

    testWidgets('가로 화면(780×360)에서도 넘치지 않고 확인했어요가 화면 안에 있다(위쪽만 스크롤)', (tester) async {
      tester.view.physicalSize = const Size(780, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repository.nextResult = const Success(AvatarReady(_url));

      await pump(tester);
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(AppButton)).bottom, 360 - 32);
    });

    testWidgets('좁은 폰(320 폭)에서는 칸이 비율을 지키며 줄어 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repository.nextResult = const Success(AvatarReady(_url));

      await pump(tester);

      expect(tester.takeException(), isNull);
      final cell = tester.getSize(cells.at(0));
      expect(cell.width, lessThan(140));
      expect(cell.height / cell.width, closeTo(175 / 140, 0.01));
    });

    testWidgets('확인했어요를 누르기 전에는 단계를 묻지 않고, 누르면 한 번 물은 뒤 20 으로 간다', (tester) async {
      // 받자마자 물으면 라우터가 화면을 바꿔 리빌도 05-12d 안내도 못 본다. 넘어가는 시점은 사람이 고른다.
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);
      expect(onboardingRepository.fetchCount, 0);

      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();

      expect(onboardingRepository.fetchCount, 1);
      expect(find.text(_referralStub), findsOneWidget);
    });

    group('실제 글꼴(Pretendard)로 잰 pen 자리', () {
      setUpAll(loadPretendard);

      // 제목은 줄바꿈 문자로 두 줄(64.8) — 비교 줄이 pen 자리 y153(64 + 64.8 + 24 = 152.8)에 온다.
      testWidgets('제목 두 줄(64.8) · 비교 줄 y153 · 설명 두 줄(42) · 홈 노출 안내 한 줄(21) · 버튼 y696', (tester) async {
        penSize(tester);
        repository.nextResult = const Success(AvatarReady(_url));
        await pump(tester);

        final title = tester.getRect(find.text(_revealTitle));
        expect(title.height, closeTo(24 * 1.35 * 2, 1));
        expect(tester.getRect(cells.at(0)).top, closeTo(64 + 24 * 1.35 * 2 + 24, 1));
        expect(tester.getRect(find.text(_revealBody)).height, closeTo(14 * 1.5 * 2, 1));
        // "흐리게 처리한" 을 뺀 새 문구(10-17)는 312 폭에 한 줄로 들어간다(종전 두 줄 42).
        expect(tester.getRect(find.text(_homeNotice)).height, closeTo(14 * 1.5, 1));
        expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(24, 696, 312, 52));
      });
    });
  });

  group('기본 아바타 시트(pen Q7VmU)', () {
    const sheetTitle = '기본 아바타로 대신했어요';
    const sheetBody = '서버 오류로 하트 10개 드렸어요. 설정 > 아바타 재생성 에서 다시 만들 수 있어요.';

    testWidgets('기본 아바타면 리빌 위에 시트를 띄운다 — 버튼은 확인 하나', (tester) async {
      repository.nextResult = const Success(AvatarFallback(_url, 10));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text(_revealTitle), findsOneWidget);
      expect(find.text(sheetTitle), findsOneWidget);
      expect(find.text(sheetBody), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
      expect(find.text('취소'), findsNothing);
    });

    testWidgets('얼개(360×780) — 손잡이 36×4 hairline · 안쪽 20/12/20/28 · 간격 16 · 제목 20/700 · 설명 16 body 1.5 · 확인 320×52', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarFallback(_url, 10));
      await pump(tester);
      await tester.pumpAndSettle();

      final sheet = find.ancestor(of: find.text(sheetTitle), matching: find.byType(BottomSheet));
      final sheetRect = tester.getRect(sheet);
      final handle = find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints == const BoxConstraints.tightFor(width: 36, height: 4),
      );
      final handleRect = tester.getRect(handle);
      expect(handleRect.top, sheetRect.top + 12);
      expect(handleRect.center.dx, 180);
      expect((tester.widget<Container>(handle).decoration! as BoxDecoration).color, AppColors.hairline);

      final title = tester.getRect(find.text(sheetTitle));
      expect((title.top, title.left), (handleRect.bottom + 16, 20));
      final titleStyle = tester.widget<Text>(find.text(sheetTitle)).style!;
      expect((titleStyle.fontSize, titleStyle.fontWeight, titleStyle.color), (20, FontWeight.w700, AppColors.ink));

      final body = tester.getRect(find.text(sheetBody));
      expect(body.top, title.bottom + 16);
      final bodyStyle = tester.widget<Text>(find.text(sheetBody)).style!;
      expect((bodyStyle.fontSize, bodyStyle.fontWeight, bodyStyle.color, bodyStyle.height), (16, FontWeight.w400, AppColors.body, 1.5));

      final button = tester.getRect(find.widgetWithText(AppButton, '확인'));
      expect(button, Rect.fromLTWH(20, body.bottom + 16, 320, 52));
      expect(sheetRect.bottom, button.bottom + 28);
      expect(sheetRect.width, 360);
    });

    testWidgets('확인을 누르면 시트가 닫히고 단계를 한 번 물은 뒤 20 으로 간다', (tester) async {
      repository.nextResult = const Success(AvatarFallback(_url, 10));
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text(sheetTitle), findsNothing);
      expect(onboardingRepository.fetchCount, 1);
      expect(find.text(_referralStub), findsOneWidget);
    });
  });

  group('완성 공개(DESIGN §7 standard — emphasis 는 하루 두 번 규칙에 들지 않아 쓰지 않는다)', () {
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

    testWidgets('만드는 중 → 리빌은 standard(220ms) 동안 겹쳐 바뀐다(바로 갈아끼우지 않는다)', (tester) async {
      await pumpUntilReady(tester);

      expect(find.text(_revealTitle), findsOneWidget);
      expect(find.text('아바타를 만들고 있어요'), findsOneWidget); // 아직 사라지는 중
      expect(opacityOf(tester, _revealTitle), 0);

      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));
      expect(find.text('아바타를 만들고 있어요'), findsNothing);
      expect(opacityOf(tester, _revealTitle), 1);
    });

    testWidgets('바뀌는 중에도 확인했어요를 누를 수 있다', (tester) async {
      await pumpUntilReady(tester);

      await tester.tap(find.text(_confirmLabel));
      await tester.pump();
      expect(onboardingRepository.fetchCount, 1);
    });

    testWidgets('기기 "동작 줄이기" 면 바로 리빌이고 pumpAndSettle 이 끝난다', (tester) async {
      reduceMotion(tester);
      repository.nextResult = const Success(AvatarReady(_url));
      await pump(tester);

      expect(find.text('아바타를 만들고 있어요'), findsNothing);
      expect(find.text(_revealTitle), findsOneWidget);
      await tester.pumpAndSettle();
    });

    group('아바타 그림이 도착하면', () {
      late Completer<ImageInfo> arrived;

      /// 테스트 환경의 이미지 요청은 늘 400 이라, 같은 주소의 그림을 캐시에 먼저 넣어 두고 원하는 때 도착시킨다.
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
          tester.widget<AnimatedOpacity>(find.descendant(of: networkImage(_url), matching: find.byType(AnimatedOpacity)));
      AnimatedScale grow(WidgetTester tester) =>
          tester.widget<AnimatedScale>(find.descendant(of: networkImage(_url), matching: find.byType(AnimatedScale)));

      testWidgets('오기 전에는 투명 · 0.96 이고, 오면 standard 동안 1 · 1 로 나타난다', (tester) async {
        holdImage();
        repository.nextResult = const Success(AvatarReady(_url));
        await pump(tester);

        expect((reveal(tester).opacity, grow(tester).scale), (0, 0.96));
        await arrive(tester);

        expect((reveal(tester).opacity, grow(tester).scale), (1, 1));
        expect((reveal(tester).duration, reveal(tester).curve), (AppMotion.standard, AppMotion.standardCurve));
        expect((grow(tester).duration, grow(tester).curve), (AppMotion.standard, AppMotion.standardCurve));
        // 칸 자리는 처음부터 140×175 — 커지는 것은 그림(transform)뿐이라 자리가 흔들리지 않는다.
        expect(tester.getSize(cells.at(1)), const Size(140, 175));
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

  // pen 05-12 `OgHRY` · 05-12b `euW4T`/`c7QuSm` 얼개(대장 전달 값 10-17) — 앱바 · 진행 막대 없이 위 64 → 제목 → 8 → 부제 → 32 →
  // 상태 틀(328 · 최소 340 · 위 45 · 안 간격 12: 마스코트 220 → 스피너 28 / 힌트 13). 바깥 [0,16,28,16].
  group('만드는 중 · 실패 얼개(pen 05-12 · 05-12b)', () {
    const failedTitle = '아바타 생성에 실패했어요';
    const freeHint = '5번까지는 무료로 다시 시도할 수 있어요';
    // pen 원문(대장 전달 10-15 · 10-17). 05-12b 의 "시도해주세요" 는 원문 그대로 붙여 쓴다.
    const generatingSubtitle = '선택한 사진으로 아바타를 만드는 중이에요. 잠시만 기다려 주세요.';
    const failedSubtitle = '사진이 흐릿하거나 서버가 혼잡했을 수 있어요. 다른 사진으로 다시 시도해주세요.';
    const retryLabel = '다시 시도';
    final subtitleStyle = AppTypography.body.copyWith(color: AppColors.body);

    Finder mascot(String asset) => find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is AssetImage && (widget.image as AssetImage).assetName == asset,
        );

    testWidgets('05-12 — 제목 y64 x16 24/700 ink · 파란 목도리 마스코트 220 · 그 아래 12 에 스피너 28 muted · 버튼 없음', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarPending());
      await pump(tester);

      final title = find.text('아바타를 만들고 있어요');
      expect(tester.widget<Text>(title).style, AppTypography.headline.copyWith(color: AppColors.ink));
      expect(tester.getRect(title).top, 64);
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

    testWidgets('05-12b — 제목 y64 · 부제 · 분홍 목도리 마스코트 · 힌트 13/400 muted · 다시 시도 328×52 바닥 28 위', (tester) async {
      penSize(tester);
      repository.nextResult = const Success(AvatarFailed());
      await pump(tester);
      await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

      final title = find.text(failedTitle);
      expect(tester.widget<Text>(title).style, AppTypography.headline.copyWith(color: AppColors.ink));
      expect(tester.getRect(title).top, 64);
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

      expect(find.widgetWithText(AppButton, retryLabel), findsOneWidget);
      expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(16, 700, 328, 52));
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

    // 부제는 328 폭에서 두 줄로 접혀 마스코트가 y233 이다(64 + 32.4 + 8 + 25.6 × 2 + 32 + 45 = 232.6 — 대장 값에서 계산한 자리,
    // 종전 앱바 56 + 위 24 일 때는 y249). 시험 기본 글꼴(Ahem)은 줄 수를 못 믿는다 — 실제 글꼴 Pretendard 로 잰다.
    group('실제 글꼴(Pretendard)로 잰 pen 자리', () {
      setUpAll(loadPretendard);

      for (final (status, subtitleText, asset) in [
        (const AvatarPending() as AvatarGenerationOutcome, generatingSubtitle, 'assets/images/mascot-male-waiting.png'),
        (const AvatarFailed() as AvatarGenerationOutcome, failedSubtitle, 'assets/images/mascot-female-sad.png'),
      ]) {
        testWidgets('부제 두 줄(51.2) · 마스코트 y233 — ${status.runtimeType}', (tester) async {
          penSize(tester);
          repository.nextResult = Success(status);
          await pump(tester);
          await tester.pump(AppMotion.standard + const Duration(milliseconds: 1));

          expect(tester.getRect(find.text(subtitleText)).height, closeTo(16 * 1.6 * 2, 1));
          expect(tester.getRect(mascot(asset)).top, closeTo(233, 1));
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

  // main.dart 와 같은 모양으로 실제 라우터(redirect · refreshListenable)를 세운다 — 단계가 바뀌어도 리빌에 남는지 본다.
  group('실제 라우터', () {
    Future<OnboardingStepListenable> pumpWithRouter(WidgetTester tester, OnboardingStep server) async {
      onboardingRepository.nextResult = Success(server);
      final container = ProviderContainer(
        overrides: [
          avatarRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          meRepositoryProvider.overrideWithValue(me),
          referralRepositoryProvider.overrideWithValue(FakeReferralRepository()),
          // 홈으로 잘못 튕겼을 때 홈이 오류 없이 그려져야 "홈에 갔다" 로 떨어진다.
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        ],
      );
      addTearDown(container.dispose);
      final steps = container.read(onboardingStepListenableProvider);
      await steps.refresh();
      final router = AppRouter.create(
        isAuthenticated: () => true,
        verificationGate: () => VerificationGate.complete,
        onboardingStep: () => steps.value,
        refreshListenable: steps,
      );
      addTearDown(router.dispose);
      router.go(AppRoutes.onboardingAvatar);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return steps;
    }

    testWidgets('기다리는 중에 단계가 complete 로 바뀌어도(토큰 갱신) 아바타 화면에 남는다', (tester) async {
      repository.nextResult = const Success(AvatarPending());
      final steps = await pumpWithRouter(tester, OnboardingStep.avatar);
      expect(find.byType(AvatarGenerationScreen), findsOneWidget);

      onboardingRepository.nextResult = const Success(OnboardingStep.complete);
      await steps.refresh();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AvatarGenerationScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('가입을 마친 사람(06-3 저장 순간 complete)도 리빌을 보고, 확인했어요 → 20 추천 코드 화면', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));
      await pumpWithRouter(tester, OnboardingStep.complete);
      expect(find.text(_revealTitle), findsOneWidget);

      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();

      expect(find.byType(ReferralCodeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('단계를 다시 물었는데 아직 avatar 면(조회 실패 등) 20 으로 못 가고 리빌에 남는다', (tester) async {
      repository.nextResult = const Success(AvatarReady(_url));
      await pumpWithRouter(tester, OnboardingStep.avatar);
      onboardingRepository.nextResult = const FailureResult(NetworkFailure());

      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();

      expect(find.byType(ReferralCodeScreen), findsNothing);
      expect(find.text(_revealTitle), findsOneWidget);
    });
  });
}

