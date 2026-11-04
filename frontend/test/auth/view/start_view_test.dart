import 'package:campus_mate/account/model/data/login_notice.dart';
import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/view/social_login_button.dart';
import 'package:campus_mate/auth/view/start_view.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/store/view/pretendard.dart';
import '../../core/supabase/fake_auth_session.dart';
import '../model/fake_social_login_repository.dart';

const _notice = '학교 메일 인증은 가입할 때 한 번만 해요';

/// 스플래시 문구(pen 01 스플래시 `eATMq`, 대장 전달 2026-11-03 — 종전 "인증된 대학생과의 소중한 인연").
const _subtitle = '인증된 사람과 소중한 인연';

/// 휴대폰 크기(360×740)에 시작 화면을 띄운다.
Future<(FakeAuthSession, FakeSocialLoginRepository)> _pump(
  WidgetTester tester, {
  bool signedIn = false,
  double textScale = 1,
  Size size = const Size(360, 740),
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = FakeAuthSession(signedIn: signedIn);
  addTearDown(session.dispose);
  final repository = FakeSocialLoginRepository();
  final container = ProviderContainer(
    overrides: [
      authSessionListenableProvider.overrideWithValue(session.listenable),
      socialLoginRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(size: size, padding: padding, textScaler: TextScaler.linear(textScale)),
          child: const StartView(),
        ),
      ),
    ),
  );
  await tester.pump();
  return (session, repository);
}

Finder _button(SocialProvider provider) =>
    find.byWidgetPredicate((widget) => widget is SocialLoginButton && widget.provider == provider);

InkWell _inkOf(WidgetTester tester, SocialProvider provider) =>
    tester.widget<InkWell>(find.descendant(of: _button(provider), matching: find.byType(InkWell)));

void main() {
  tearDown(LoginNotice.take);

  // pen 01 스플래시 `EbdUI` (대장 전달 2026-11-03, 사용자 결정: 1.0.2 부터 날짜 조건 없이 늘 이 장면): 크리스마스 장면이 화면 전체 배경(360×780, cover).
  // 글자 로고 "CampusMate"(`NNsOs`)와 혼자 선 마스코트(`OkZx9`)는 숨김(장면 안에 로고 · 토끼가 있다).
  // 문구 `eATMq` 16/400 #6A6A6A 가운데 y462(높이 26). 소셜 버튼 묶음 `hbnCW` 은 기존 자리 그대로.
  group('크리스마스 장면 배경 (pen EbdUI)', () {
    testWidgets('장면(splashChristmas)이 화면 전체를 cover 로 덮고, 옛 글자 로고 · 마스코트 · 스피너는 없다', (tester) async {
      await _pump(tester, signedIn: true, size: const Size(360, 780));

      final scene = find.byType(AppLottieView);
      expect(tester.widget<AppLottieView>(scene).scene, AppLottie.splashChristmas);
      expect(tester.widget<AppLottieView>(scene).fit, BoxFit.cover);
      expect(tester.getRect(scene), const Rect.fromLTWH(0, 0, 360, 780));
      expect(find.text('CampusMate'), findsNothing);
      expect(find.image(const AssetImage('assets/images/mascot-female.png')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('장면 안 로고를 낭독기가 "CampusMate" 로 읽는다(글자 로고를 대신한다)', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, signedIn: true);

      expect(find.bySemanticsLabel('CampusMate'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('문구는 16/400 #6A6A6A 가운데, 360×780 에서 위 y462 · 높이 26', (tester) async {
      await _pump(tester, signedIn: true, size: const Size(360, 780));

      final text = tester.widget<Text>(find.text(_subtitle));
      expect(text.style, AppTypography.body.copyWith(color: AppColors.muted));
      expect(text.textAlign, TextAlign.center);
      final rect = tester.getRect(find.text(_subtitle));
      expect(rect.top, closeTo(462, 0.5));
      expect(rect.height, closeTo(26, 0.5));
      expect(rect.center.dx, closeTo(180, 0.5));
    });

    // CLAUDE.md 규칙 3: 좁고 낮은 화면(320×568)에서 iOS 소셜 버튼 3개 묶음이 문구와 겹치지 않는다 — 문구가 버튼 묶음 위로 밀린다.
    testWidgets('320×568 iOS(버튼 3개)에서도 문구가 버튼 묶음과 겹치지 않고 화면 안에 있다', (tester) async {
      await _pump(tester, size: const Size(320, 568));

      final tagline = tester.getRect(find.text(_subtitle));
      final buttons = tester.getRect(find.byKey(StartView.loginAreaKey));
      expect(tagline.bottom, lessThanOrEqualTo(buttons.top));
      expect(tagline.top, greaterThanOrEqualTo(0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('넉넉한 화면(360×780)에서는 밀리지 않고 pen 자리(y462) 그대로다', (tester) async {
      await _pump(tester, size: const Size(360, 780));

      expect(tester.getRect(find.text(_subtitle)).top, closeTo(462, 0.5));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    // 실기기: 상태 표시줄(위 40) · 홈 막대(아래 20). 장면은 안전 영역 밖(화면 전체)이 기준이라 문구도 화면 좌표 y462 에 있어야 하고,
    // 소셜 버튼 묶음은 안전 영역 안이라 화면 좌표로 견준다.
    const notchInsets = EdgeInsets.only(top: 40, bottom: 20);

    testWidgets('상태 표시줄 40 · 홈 막대 20 이 있어도 문구는 화면 좌표 y462(장면 로고 바로 아래)에 선다', (tester) async {
      await _pump(tester, signedIn: true, size: const Size(360, 780), padding: notchInsets);

      expect(tester.getRect(find.byType(AppLottieView)), const Rect.fromLTWH(0, 0, 360, 780));
      expect(tester.getRect(find.text(_subtitle)).top, closeTo(462, 0.5));
    });

    testWidgets('상태 표시줄 40 · 홈 막대 20 이 있는 320×568 iOS 에서도 문구가 버튼 묶음과 겹치지 않는다', (tester) async {
      await _pump(tester, size: const Size(320, 568), padding: notchInsets);

      final tagline = tester.getRect(find.text(_subtitle));
      final buttons = tester.getRect(find.byKey(StartView.loginAreaKey));
      expect(buttons.bottom, 568 - 20 - 28, reason: '버튼 묶음은 안전 영역 안(홈 막대 20 + 아래 28)');
      expect(tagline.bottom, lessThanOrEqualTo(buttons.top));
      expect(tagline.top, greaterThanOrEqualTo(0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('문구는 장면을 따라 간다 — 장면이 cover 로 줄거나 늘면 같은 비율의 자리(360×740 → 442, 412×915 → 542)', (tester) async {
      await _pump(tester, signedIn: true, size: const Size(360, 740));
      expect(tester.getRect(find.text(_subtitle)).top, closeTo(462 - 20, 0.5));

      await _pump(tester, signedIn: true, size: const Size(412, 915));
      expect(tester.getRect(find.text(_subtitle)).top, closeTo(462 * 915 / 780, 0.5));
    });
  });

  group('세션 확인 전 · 로그인 상태(게이트가 다음 화면으로 보내는 동안)', () {
    testWidgets('버튼 영역과 안내 줄을 그리지 않는다(누를 수도, 읽을 수도 없다)', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, signedIn: true);

      expect(tester.widget<Visibility>(find.byKey(StartView.loginAreaKey)).visible, isFalse);
      expect(find.byType(SocialLoginButton).hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('카카오로 로그인'), findsNothing);
      expect(find.bySemanticsLabel(_notice), findsNothing);
      handle.dispose();
    });

    testWidgets('버튼 자리는 비워 두어 로그아웃이 확인돼도 문구가 움직이지 않는다', (tester) async {
      final (session, _) = await _pump(tester, signedIn: true);
      final before = tester.getRect(find.text(_subtitle));

      session.signOut();
      await tester.pump();

      expect(tester.widget<Visibility>(find.byKey(StartView.loginAreaKey)).visible, isTrue);
      expect(tester.getRect(find.text(_subtitle)), before);
    });

    testWidgets('로그인되면(소셜 로그인 성공) 버튼 영역을 다시 거둔다', (tester) async {
      final (session, _) = await _pump(tester);

      session.signIn();
      await tester.pump();

      expect(find.byType(SocialLoginButton).hitTestable(), findsNothing);
    });
  });

  group('로그아웃이 확인된 뒤', () {
    testWidgets('카카오 → 구글 순서, 세로 간격 12, 좌우 24 를 뺀 같은 폭, 애플 버튼은 없다', (tester) async {
      await _pump(tester);

      final kakao = tester.getRect(_button(SocialProvider.kakao).hitTestable());
      final google = tester.getRect(_button(SocialProvider.google).hitTestable());
      expect(google.top - kakao.bottom, 12);
      expect((kakao.left, kakao.width), (24, 360 - 48));
      expect((google.left, google.width), (24, 360 - 48));
      expect(_button(SocialProvider.apple), findsNothing);
    });

    testWidgets('맨 아래에 14px 회색 안내 줄이 가운데 있다', (tester) async {
      await _pump(tester);

      final notice = tester.widget<Text>(find.text(_notice));
      expect(notice.style?.color, AppColors.muted);
      // 대장 지시문 15(디자인 파일 값): 14px(줄 높이 20 은 아래 간격 시험이 본다).
      expect(notice.style?.fontSize, 14);
      expect(notice.textAlign, TextAlign.center);
      expect(tester.getRect(find.text(_notice)).top, greaterThan(tester.getRect(_button(SocialProvider.google)).bottom));
      expect(tester.getCenter(find.text(_notice)).dx, moreOrLessEquals(180, epsilon: 0.5));
    });
  });

  // 후속 지시문 13 B-2: 마지막 버튼 아래 12, 안내 줄 위 padding 4, 줄 높이 20, 영역 아래 28.
  testWidgets('안내 줄은 마지막 버튼 아래 12 + 줄 위 4, 줄 높이 20, 화면 맨 아래까지 28', (tester) async {
    // 시험 글꼴은 글자마다 1em 폭이라 14px 24자(띄어쓰기 포함)가 360 폭(칸 312)에서 두 줄로 꺾인다.
    // 실제 Pretendard 로는 한 줄이다 — 한 줄로 그려지는 412 폭(흔한 안드로이드 폭)에서 잰다.
    await _pump(tester, size: const Size(412, 915));

    final google = tester.getRect(_button(SocialProvider.google));
    final notice = tester.getRect(find.text(_notice));
    expect(notice.top - google.bottom, 12 + 4);
    expect(notice.height, 20);
    expect(915 - notice.bottom, 28);
    final style = tester.widget<Text>(find.text(_notice)).style!;
    expect(style.fontSize! * style.height!, moreOrLessEquals(20));
  });

  group('로그인 진행', () {
    testWidgets('누르면 그 버튼만 스피너(심볼 유지), 나머지는 비활성, 진행 중 탭은 무시한다', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.kakao));
      await tester.pump();

      expect(find.descendant(of: _button(SocialProvider.kakao), matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(find.descendant(of: _button(SocialProvider.kakao), matching: find.byKey(SocialLoginButton.markKey)),
          findsOneWidget);
      expect(_inkOf(tester, SocialProvider.google).onTap, isNull);
      await tester.tap(_button(SocialProvider.google));
      await tester.tap(_button(SocialProvider.kakao));
      expect(repository.requested, [SocialProvider.kakao]);
    });

    testWidgets('실패하면 버튼 영역 바로 위에 경고 아이콘 실패 토스트가 버튼 폭으로 뜨고, 몇 초 뒤 사라진다', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.google));
      repository.completer.complete(const FailureResult(SocialLoginFailure()));
      await tester.pump();
      await tester.pump();

      const message = '로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요';
      final toast = tester.getRect(find.byKey(StartView.toastKey));
      final kakao = tester.getRect(_button(SocialProvider.kakao));
      expect(find.text(message), findsOneWidget);
      expect(find.descendant(of: find.byKey(StartView.toastKey), matching: find.byIcon(AppIcons.alertTriangle)),
          findsOneWidget);
      expect(kakao.top - toast.bottom, 12);
      expect((toast.left, toast.width), (kakao.left, kakao.width));
      // 두 줄이면 높이 60(후속 지시문 13 B-3).
      expect(tester.getSize(find.text(message)).height, 40);
      expect(toast.height, 60);
      expect(_inkOf(tester, SocialProvider.kakao).onTap, isNotNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text(message), findsNothing);
    });

    testWidgets('취소면 info 아이콘 취소 토스트(내용 폭 · 높이 40)', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.kakao));
      repository.completer.complete(const FailureResult(LoginCancelledFailure()));
      await tester.pump();
      await tester.pump();

      // 후속 지시문 13 B-3: 취소 토스트는 폭을 내용에 맞추고 info 아이콘, 높이 40, 버튼 영역 바로 위 가운데.
      expect(find.text('로그인이 취소됐어요'), findsOneWidget);
      expect(find.descendant(of: find.byKey(StartView.toastKey), matching: find.byIcon(AppIcons.info)), findsOneWidget);
      expect(find.descendant(of: find.byKey(StartView.toastKey), matching: find.byIcon(AppIcons.alertTriangle)),
          findsNothing);
      final toast = tester.getRect(find.byKey(StartView.toastKey));
      final kakao = tester.getRect(_button(SocialProvider.kakao));
      expect(toast.width, lessThan(kakao.width));
      expect(toast.center.dx, moreOrLessEquals(kakao.center.dx, epsilon: 0.5));
      expect(toast.height, 40);
      expect(kakao.top - toast.bottom, 12);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('토스트 바탕은 짙은 #222222, 글씨는 흰색 굵게', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.kakao));
      repository.completer.complete(const FailureResult(LoginCancelledFailure()));
      await tester.pump();
      await tester.pump();

      final box = tester.widget<Container>(
        find.descendant(of: find.byKey(StartView.toastKey), matching: find.byType(Container)).first,
      );
      expect((box.decoration! as BoxDecoration).color, AppColors.surfaceInk);
      final text = tester.widget<Text>(find.text('로그인이 취소됐어요'));
      expect(text.style?.color, AppColors.onInk);
      expect(text.style!.fontWeight!.value, greaterThanOrEqualTo(FontWeight.w600.value));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  // pen `jXJSY` 시작 화면 4종: 애플 버튼은 iOS 에서만, 구글 아래 12.
  group('플랫폼별 버튼', () {
    final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

    testWidgets('iOS: 카카오 → 구글 → 애플 순서, 세로 간격 12, 셋 다 좌우 24 를 뺀 같은 폭 · 높이 46', (tester) async {
      await _pump(tester);

      final kakao = tester.getRect(_button(SocialProvider.kakao).hitTestable());
      final google = tester.getRect(_button(SocialProvider.google).hitTestable());
      final apple = tester.getRect(_button(SocialProvider.apple).hitTestable());
      expect(google.top - kakao.bottom, 12);
      expect(apple.top - google.bottom, 12);
      for (final rect in [kakao, google, apple]) {
        expect((rect.left, rect.width, rect.height), (24, 360 - 48, 46));
      }
      expect(find.text('Apple로 로그인'), findsOneWidget);
      // 안내 줄은 맨 아래 버튼(애플) 밑에 온다.
      expect(tester.getRect(find.text(_notice)).top, greaterThan(apple.bottom));
    }, variant: ios);

    testWidgets('안드로이드: 카카오 · 구글 둘뿐, 애플 버튼은 없다', (tester) async {
      await _pump(tester);

      expect(find.byType(SocialLoginButton), findsNWidgets(2));
      expect(_button(SocialProvider.apple), findsNothing);
      expect(find.textContaining('Apple'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS: 애플을 누르면 애플 버튼만 덮개 + 스피너, 카카오 · 구글은 눌리지 않고 진행 중 탭은 무시한다', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.apple));
      await tester.pump();

      expect(find.descendant(of: _button(SocialProvider.apple), matching: find.byKey(SocialLoginButton.busyOverlayKey)),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_inkOf(tester, SocialProvider.kakao).onTap, isNull);
      expect(_inkOf(tester, SocialProvider.google).onTap, isNull);
      await tester.tap(_button(SocialProvider.kakao));
      await tester.tap(_button(SocialProvider.google));
      await tester.tap(_button(SocialProvider.apple));
      expect(repository.requested, [SocialProvider.apple]);
    }, variant: ios);

    testWidgets('iOS: 카카오가 진행 중이면 애플도 눌리지 않는다', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.kakao));
      await tester.pump();

      expect(_inkOf(tester, SocialProvider.apple).onTap, isNull);
      expect(find.byKey(SocialLoginButton.busyOverlayKey), findsNothing);
      await tester.tap(_button(SocialProvider.apple));
      expect(repository.requested, [SocialProvider.kakao]);
    }, variant: ios);

    testWidgets('iOS: 애플 창을 닫으면 취소 토스트가 뜨고 버튼이 다시 눌린다', (tester) async {
      final (_, repository) = await _pump(tester);

      await tester.tap(_button(SocialProvider.apple));
      repository.completer.complete(const FailureResult(LoginCancelledFailure()));
      await tester.pump();
      await tester.pump();

      expect(find.text('로그인이 취소됐어요'), findsOneWidget);
      expect(find.byKey(SocialLoginButton.busyOverlayKey), findsNothing);
      expect(_inkOf(tester, SocialProvider.apple).onTap, isNotNull);
      await tester.pump(const Duration(seconds: 3));
    }, variant: ios);

    for (final scale in [1.0, 1.5, 2.0]) {
      for (final size in [const Size(360, 740), const Size(320, 568)]) {
        testWidgets('iOS: $scale배 · ${size.width.toInt()}×${size.height.toInt()} 에서 버튼 셋이 넘치지 않는다(실패 토스트 포함)',
            (tester) async {
          final (_, repository) = await _pump(tester, textScale: scale, size: size);

          await tester.tap(_button(SocialProvider.apple));
          repository.completer.complete(const FailureResult(SocialLoginFailure()));
          await tester.pump();
          await tester.pump();

          expect(tester.takeException(), isNull);
          for (final provider in SocialProvider.values) {
            expect(tester.getSize(_button(provider)).height, 46);
          }
          await tester.pump(const Duration(seconds: 3));
        }, variant: ios);
      }
    }
  });

  testWidgets('로그아웃하며 남긴 알림(탈퇴 등)을 토스트로 한 번 보여준다', (tester) async {
    LoginNotice.post('탈퇴한 계정이에요');

    await _pump(tester);
    await tester.pump();

    expect(find.text('탈퇴한 계정이에요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('탈퇴한 계정이에요'), findsNothing);
  });

  // 03 학교 메일 충돌에서 "카카오로 다시 로그인" 을 누르면 로그아웃하며 남긴 안내(10-17 학생증 제거 B안).
  // pen 값(대장 전달, 노드 id 미전달): 312×58 두 줄 알약 · #222222 · info 16 흰색 · 14/600 흰색 · 화면 안 (24,482).
  testWidgets('다시 로그인 안내(info)는 버튼 폭 두 줄 알약에 info 아이콘으로 한 번 뜬다(360×780 에서 x24)', (tester) async {
    const message = '이 학교 메일은 카카오로 가입돼 있어요. 카카오로 로그인해 주세요';
    LoginNotice.post(message, isInfo: true);

    await _pump(tester, size: const Size(360, 780));
    await tester.pump();

    final toast = tester.getRect(find.byKey(StartView.toastKey));
    expect(find.text(message), findsOneWidget);
    expect(find.descendant(of: find.byKey(StartView.toastKey), matching: find.byIcon(AppIcons.info)), findsOneWidget);
    expect(find.descendant(of: find.byKey(StartView.toastKey), matching: find.byIcon(AppIcons.alertTriangle)), findsNothing);
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.info));
    expect((icon.size, icon.color), (16, AppColors.onInk));
    final text = tester.widget<Text>(find.text(message));
    expect((text.style?.fontSize, text.style?.fontWeight, text.style?.color), (14, FontWeight.w600, AppColors.onInk));
    expect((toast.left, toast.width), (24, 312));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text(message), findsNothing);
  });

  group('글자 배율', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final size in [const Size(360, 740), const Size(320, 568)]) {
        testWidgets('$scale배 · ${size.width.toInt()}×${size.height.toInt()} 에서 넘치지 않는다(토스트 2줄 포함)', (tester) async {
          final (_, repository) = await _pump(tester, textScale: scale, size: size);

          await tester.tap(_button(SocialProvider.kakao));
          repository.completer.complete(const FailureResult(SocialLoginFailure()));
          await tester.pump();
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_button(SocialProvider.kakao)).height, 46);
          await tester.pump(const Duration(seconds: 3));
        });
      }
    }
  });

  // 시작 화면은 앱의 맨 아래 화면이다 — 안드로이드 뒤로가기가 앱을 바로 닫지 않는다. 안내는 자기 토스트 자리(버튼 바로 위)에 띄운다.
  group('뒤로가기 확인', () {
    late int exitCalls;

    setUp(() => exitCalls = 0);

    Future<void> pumpAndroid(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester);
    }

    testWidgets('안드로이드: 첫 뒤로가기는 info 토스트만 띄우고, 2초 안에 한 번 더 누르면 앱을 닫는다', (tester) async {
      await pumpAndroid(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text(backExitMessage), findsOneWidget);
      expect(find.byKey(StartView.toastKey), findsOneWidget);
      expect(find.descendant(of: find.byKey(StartView.toastKey), matching: find.byIcon(AppIcons.info)), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(exitCalls, 1);
      await tester.pump(const Duration(seconds: 3));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('iOS: 가로채지 않는다', (tester) async {
      await pumpAndroid(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text(backExitMessage), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  // 실제 글꼴이라야 줄 수가 pen 과 같다 — 아래 부제 묶음과 같이 파일 끝에 둔다.
  testWidgets('다시 로그인 안내는 실제 글꼴로 두 줄 · 알약 312 폭, 360×780 화면 안 (24, 482)', (tester) async {
    await tester.runAsync(loadPretendard);
    const message = '이 학교 메일은 카카오로 가입돼 있어요. 카카오로 로그인해 주세요';
    LoginNotice.post(message, isInfo: true);

    await _pump(tester, size: const Size(360, 780));
    await tester.pump();

    final toast = tester.getRect(find.byKey(StartView.toastKey));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(message));
    final painter = TextPainter(text: paragraph.text, textDirection: TextDirection.ltr, textScaler: paragraph.textScaler)
      ..layout(maxWidth: paragraph.constraints.maxWidth);
    expect(painter.computeLineMetrics().length, 2);
    painter.dispose();
    expect((toast.left, toast.top, toast.width), (24, 482, 312));
    // pen 높이 58 · 앱 60 — 공용 AppToast 줄높이 20(마스터 `I8UOWm` 렌더 값)을 그대로 쓴다. 차이는 보고에 남겼다.
    expect(toast.height, 60);
    await tester.pump(const Duration(seconds: 3));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  // 반드시 파일 맨 끝 — 여기서 실제 글꼴(Pretendard)을 불러오면 그 뒤 시험 글꼴이 바뀐다(앞 시험들은 Ahem 폭을 가정한다).
  group('부제 "$_subtitle" — 실제 글꼴로 잰다', () {
    int lines(WidgetTester tester) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(_subtitle));
      final painter = TextPainter(text: paragraph.text, textDirection: TextDirection.ltr, textScaler: paragraph.textScaler)
        ..layout(maxWidth: paragraph.constraints.maxWidth);
      final count = painter.computeLineMetrics().length;
      painter.dispose();
      return count;
    }

    for (final size in [const Size(360, 740), const Size(320, 568)]) {
      testWidgets('16/400 muted, ${size.width.toInt()} 폭(좌우 24 를 뺀 칸)에서 한 줄', (tester) async {
        await tester.runAsync(loadPretendard);
        await _pump(tester, signedIn: true, size: size);

        final style = tester.widget<Text>(find.text(_subtitle)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (16.0, FontWeight.w400, AppColors.muted));
        expect(lines(tester), 1);
      });
    }

    for (final scale in [1.3, 1.5, 2.0]) {
      testWidgets('글자 $scale배 · 320 폭에서도 넘치거나 잘리지 않는다(모자라면 줄을 바꾼다)', (tester) async {
        await tester.runAsync(loadPretendard);
        await _pump(tester, signedIn: true, textScale: scale, size: const Size(320, 568));

        expect(tester.takeException(), isNull);
        final paragraph = tester.renderObject<RenderParagraph>(find.text(_subtitle));
        expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5));
        expect(paragraph.size.width, lessThanOrEqualTo(320 - 48));
      });
    }
  });
}
