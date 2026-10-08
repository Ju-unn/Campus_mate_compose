import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/social_login_repository_provider.dart';
import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/view/social_login_button.dart';
import 'package:campus_mate/auth/view/start_view.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/supabase/fake_auth_session.dart';
import '../model/fake_social_login_repository.dart';

const _notice = '학교 메일 인증은 가입할 때 한 번만 해요';

/// 휴대폰 크기(360×740)에 시작 화면을 띄운다.
Future<(FakeAuthSession, FakeSocialLoginRepository)> _pump(
  WidgetTester tester, {
  bool signedIn = false,
  double textScale = 1,
  Size size = const Size(360, 740),
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
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
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

  group('지금 스플래시 그대로인 위쪽', () {
    testWidgets('마스코트 · 빨간 "CampusMate" · 부제를 보이고, 스피너는 없다', (tester) async {
      await _pump(tester, signedIn: true);

      expect(find.byKey(StartView.mascotKey), findsOneWidget);
      expect(find.text('하루 한 사람, 같은 캠퍼스에서'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final title = tester.widget<Text>(find.text('CampusMate'));
      expect(title.style?.fontSize, AppTypography.display.fontSize);
      expect(title.style?.color, AppColors.primary);
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

    testWidgets('버튼 자리는 비워 두어 로그아웃이 확인돼도 마스코트가 움직이지 않는다', (tester) async {
      final (session, _) = await _pump(tester, signedIn: true);
      final before = tester.getRect(find.byKey(StartView.mascotKey));

      session.signOut();
      await tester.pump();

      expect(tester.widget<Visibility>(find.byKey(StartView.loginAreaKey)).visible, isTrue);
      expect(tester.getRect(find.byKey(StartView.mascotKey)), before);
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

    testWidgets('맨 아래에 작은 회색 안내 줄이 가운데 있다', (tester) async {
      await _pump(tester);

      final notice = tester.widget<Text>(find.text(_notice));
      expect(notice.style?.color, AppColors.muted);
      expect(notice.style?.fontSize, AppTypography.caption.fontSize);
      expect(notice.textAlign, TextAlign.center);
      expect(tester.getRect(find.text(_notice)).top, greaterThan(tester.getRect(_button(SocialProvider.google)).bottom));
      expect(tester.getCenter(find.text(_notice)).dx, moreOrLessEquals(180, epsilon: 0.5));
    });
  });

  // 후속 지시문 13 B-2: 마지막 버튼 아래 12, 안내 줄 위 padding 4, 줄 높이 20, 영역 아래 28.
  testWidgets('안내 줄은 마지막 버튼 아래 12 + 줄 위 4, 줄 높이 20, 화면 맨 아래까지 28', (tester) async {
    await _pump(tester);

    final google = tester.getRect(_button(SocialProvider.google));
    final notice = tester.getRect(find.text(_notice));
    expect(notice.top - google.bottom, 12 + 4);
    expect(notice.height, 20);
    expect(740 - notice.bottom, 28);
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

  testWidgets('로그아웃하며 남긴 알림(탈퇴 등)을 토스트로 한 번 보여준다', (tester) async {
    LoginNotice.post('탈퇴한 계정이에요');

    await _pump(tester);
    await tester.pump();

    expect(find.text('탈퇴한 계정이에요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('탈퇴한 계정이에요'), findsNothing);
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
}
