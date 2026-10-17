import 'dart:async';

import 'package:campus_mate/account/model/login_notice.dart';
import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/profile/view/hint_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../model/fake_school_email_repository.dart';
import '../model/fake_verification_gate_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    FakeSchoolEmailRepository? repository,
    DateTime Function()? now,
  }) async {
    final container = ProviderContainer(
      overrides: [
        schoolEmailRepositoryProvider.overrideWithValue(repository ?? FakeSchoolEmailRepository()),
        verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
        if (now != null) verifyCodeNowProvider.overrideWithValue(now),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: VerifyCodeScreen(email: email)),
      ),
    );
    return container;
  }

  testWidgets('안내 문구·만료 타이머·메일 다시 받기를 보여준다(pen VuiDi)', (tester) async {
    final sentAt = DateTime.now();
    final container = await pumpScreen(tester, now: () => sentAt);

    expect(find.text('인증 코드를 입력해요'), findsOneWidget);
    expect(find.text('hong@snu.ac.kr 로 6자리 숫자를 보냈어요'), findsOneWidget);
    expect(find.textContaining('뒤에 만료돼요'), findsOneWidget);
    // 로그인 화면이 방금 보낸 메일이라 열리는 순간부터 60초를 센다. 남은 초 **글자** 는
    // `CountdownBuilder` 가 기기 시계를 보고 그리므로, 전체 실행이 첫 프레임까지 1초를 넘기면
    // "(59초)" 로 찍힌다 — 60초라는 약속은 상태로 확인하고, 화면은 버튼이 꺼진 채
    // 남은 초를 보여주는지만 본다.
    expect(
      container.read(verifyCodeViewModelProvider(email)).resendAvailableAt,
      sentAt.add(const Duration(seconds: 60)),
    );
    final resend = tester.widget<TextButton>(
      find.ancestor(of: find.textContaining('메일 다시 받기 ('), matching: find.byType(TextButton)),
    );
    expect(resend.enabled, isFalse);
  });

  // 값표_온보딩화면 "가입 화면 3D(1004)" jYwqT · qVa0s — 만료 줄 시계는 3D 16, 글자와 6.
  testWidgets('pen jYwqT: 만료 줄 아이콘은 시계 3D 16, 글자와 6', (tester) async {
    await pumpScreen(tester);

    final text = find.textContaining('뒤에 만료돼요');
    final row = find.ancestor(of: text, matching: find.byType(Row)).first;
    final icon3d = find.descendant(of: row, matching: find.byType(Icon3d));
    expect(tester.widget<Icon3d>(icon3d).icon, AppIcon3d.clock);
    expect(tester.getSize(icon3d), const Size(16, 16));
    expect(tester.getTopLeft(text).dx - tester.getTopRight(icon3d).dx, 6);
    expect(find.descendant(of: row, matching: find.byType(Icon)), findsNothing);
  });

  testWidgets('입력한 숫자를 여섯 칸에 한 글자씩 그린다', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('메일을 다시 받으면 입력칸이 비고 버튼이 쿨다운 동안 꺼진다', (tester) async {
    // 코드를 2분 전에 받은 화면이라 첫 쿨다운은 이미 지났다 — 그래야 버튼을 누를 수 있다.
    var now = DateTime.now().subtract(const Duration(minutes: 2));
    final container = await pumpScreen(tester, now: () => now);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    final resentAt = DateTime.now();
    now = resentAt;

    await tester.tap(find.text('메일 다시 받기'));
    await tester.pump(const Duration(milliseconds: 1));

    // 새 코드가 오는데 예전 숫자가 남아 있으면 그대로 제출된다.
    expect(find.text('1'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    // 쿨다운 동안 눌러도 아무 일이 없으므로 버튼을 끄고 남은 초를 보여준다.
    // 남은 초 **글자** 는 `CountdownBuilder` 가 기기 시계를 보고 그리므로 탭한 뒤 실제 1초가
    // 지나면 "(59초)" 다 — 60초라는 약속은 상태로 확인한다(37줄 테스트와 같은 처방).
    expect(
      container.read(verifyCodeViewModelProvider(email)).resendAvailableAt,
      resentAt.add(const Duration(seconds: 60)),
    );
    final resend = tester.widget<TextButton>(
      find.ancestor(of: find.textContaining('메일 다시 받기 ('), matching: find.byType(TextButton)),
    );
    expect(resend.enabled, isFalse);
  });

  testWidgets('기한이 지나면 만료 문구가 뜨고 확인 버튼이 꺼진다', (tester) async {
    // 카운트다운은 기기 시계를 보므로 `tester.pump(5분)` 으로는 만료되지 않는다 —
    // 코드를 받은 시각을 유효 시간의 두 배만큼 과거로 두고 화면을 연다.
    await pumpScreen(tester, now: () => DateTime.now().subtract(codeLifetime * 2));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    expect(find.text('코드가 만료됐어요. 메일을 다시 받아 주세요'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '확인')).enabled,
      isFalse,
    );
  });

  testWidgets('코드가 거부되면 여섯 칸 테두리가 오류 색으로 바뀐다', (tester) async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    await tester.pump(const Duration(milliseconds: 1));

    // pen `Vn6w4` — 테두리 error 2.
    final boxes = tester
        .widgetList<Container>(find.byType(Container))
        .where((box) => (box.decoration as BoxDecoration?)?.border != null)
        .toList();
    final errorBoxes = boxes.where((box) {
      final side = ((box.decoration! as BoxDecoration).border! as Border).top;
      return side.color == AppColors.error && side.width == 2;
    });
    expect(errorBoxes.length, 6);
  });

  // 사용자 10-16 "최초 가입시 온보딩화면에 뒤로가기 버튼이 없는게 있는거 같아" — pen VuiDi · Vn6w4 앱바(AppBar · Sub `KH1hX`, 제목 없음).
  group('03 뒤로가기 → 02', () {
    Finder back() => find.widgetWithIcon(IconButton, AppIcons.arrowLeft);

    Future<FakeSchoolEmailRepository> pumpRouted(WidgetTester tester, {FakeSchoolEmailRepository? repository}) async {
      final fake = repository ?? FakeSchoolEmailRepository();
      final container = ProviderContainer(
        overrides: [
          schoolEmailRepositoryProvider.overrideWithValue(fake),
          verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.verifyCode,
        routes: [
          GoRoute(path: AppRoutes.login, builder: (context, state) => const Scaffold(body: Text('02 학교 메일 입력'))),
          GoRoute(path: AppRoutes.verifyCode, builder: (context, state) => VerifyCodeScreen(email: email)),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      return fake;
    }

    testWidgets('앱바 56 에 뒤로 48×48(x12 · arrow-left 22 ink · 라벨 "뒤로")만 있고 제목은 없다', (tester) async {
      await pumpScreen(tester);

      expect(tester.getSize(find.byType(AppBar)).height, 56);
      expect(tester.getRect(back()), const Rect.fromLTWH(12, 4, 48, 48));
      final icon = tester.widget<Icon>(find.descendant(of: back(), matching: find.byType(Icon)));
      expect((icon.icon, icon.size, icon.color), (AppIcons.arrowLeft, 22.0, AppColors.ink));
      expect(find.byTooltip('뒤로'), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(Text)), findsNothing);
    });

    testWidgets('누르면 임시 연결을 비우고(startOver) 02 로 간다', (tester) async {
      final repository = await pumpRouted(tester);

      await tester.tap(back());
      await tester.pumpAndSettle();

      expect(repository.calls, ['discard']);
      expect(find.text('02 학교 메일 입력'), findsOneWidget);
    });

    testWidgets('안드로이드 시스템 뒤로가기도 02 로 가고 "한 번 더 누르면 종료" 안내는 뜨지 않는다', (tester) async {
      final repository = await pumpRouted(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(repository.calls, ['discard']);
      expect(find.text('02 학교 메일 입력'), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('연타해도 정리 · 이동은 한 번이다', (tester) async {
      final repository = await pumpRouted(tester);

      await tester.tap(back());
      await tester.tap(back(), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(repository.calls, ['discard']);
      expect(find.text('02 학교 메일 입력'), findsOneWidget);
    });

    testWidgets('코드를 확인하는 중에는 화살표가 꺼지고 시스템 뒤로가기도 아무 일도 하지 않는다', (tester) async {
      final repository = _HeldVerifyRepository();
      await pumpRouted(tester, repository: repository);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('확인'));
      await tester.pump(); // 서버 답을 붙잡아 둔다 — 아직 확인 중

      expect(tester.widget<IconButton>(back()).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(repository.calls, ['verifyCode']);
      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      expect(find.text(backExitMessage), findsNothing);
      repository.answer.complete(const FailureResult(WrongCodeFailure()));
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('6자리를 모두 입력하기 전에는 CTA 가 비활성이다', (tester) async {
    await pumpScreen(tester);

    // 재전송도 ElevatedButton 이라 .first 대신 라벨로 확인 버튼을 특정한다.
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '확인'));
    expect(button.enabled, isFalse);
  });

  testWidgets('코드가 틀리면 pen Vn6w4 오류 문구를 보여준다', (tester) async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    // 만료 타이머가 1초마다 다시 그려 pumpAndSettle 은 끝나지 않는다 — 가짜 저장소의 지연만큼만 민다.
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('코드가 맞지 않아요. 다시 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('검증에 실패하면 에러 문구를 보여준다', (tester) async {
    final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(UnknownFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    // 만료 타이머가 1초마다 다시 그려 pumpAndSettle 은 끝나지 않는다 — 가짜 저장소의 지연만큼만 민다.
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('알 수 없는 오류가 발생했습니다'), findsOneWidget);
  });
  // 03 학교 메일 충돌(설계 5-3 B안, 10-17 학생증 제거). pen 값은 대장이 pen 담당에게서 받은 03 오류 변형(360×780, 노드 id 미전달):
  // 제목 24 ink · 부제 16 body · 첫 줄 14/600 error + circle-alert 14 · 둘째 줄 14/400 body 줄높이 1.5 폭 312 padding [4,0,0,18] ·
  // 주 단추 AppButton primary 312×52 · 보조 TextButton 312×48 위 간격 8 · 본문 padding [0,24,28,24] · 코드 칸 · 타이머 · 다시 받기 없음.
  group('03 학교 메일 충돌(409)', () {
    const first = '이미 카카오로 가입된 학교 메일이에요';
    const second = '카카오로 로그인해 주세요';
    late List<String> signedOut;

    setUp(() => signedOut = []);
    tearDown(LoginNotice.take);

    Future<void> pumpTaken(WidgetTester tester, String owner, {String? mine, double textScale = 1}) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = FakeSchoolEmailRepository()
        ..nextCompleteResult = FailureResult(SchoolEmailTakenFailure('서버 문구', owner, myProvider: mine));
      final container = ProviderContainer(
        overrides: [
          schoolEmailRepositoryProvider.overrideWithValue(repository),
          verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
          signOutProvider.overrideWithValue(() async => signedOut.add('signOut')),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp(home: VerifyCodeScreen(email: email))),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      // 글자를 키우면 확인 버튼이 화면 밖으로 밀린다(같이 스크롤된다).
      await tester.ensureVisible(find.text('확인'));
      await tester.pump();
      await tester.tap(find.text('확인'));
      // verifyCode · complete 가 차례로 가짜 지연을 하나씩 갖는다.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('다른 소셜이 쥐면 두 줄 안내 + "카카오로 다시 로그인" + "다른 학교 메일 입력"(팝업 없음)', (tester) async {
      await pumpTaken(tester, 'kakao', mine: 'google');

      expect(find.text(first), findsOneWidget);
      expect(find.text(second), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '카카오로 다시 로그인'), findsOneWidget);
      expect(find.text('다른 학교 메일 입력'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      // 오류 변형에는 코드 칸 · 만료 줄 · 다시 받기 · 스팸함 안내 · 확인이 없다.
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('뒤에 만료돼요'), findsNothing);
      expect(find.textContaining('메일 다시 받기'), findsNothing);
      expect(find.byType(HintLine), findsNothing);
      expect(find.text('확인'), findsNothing);
      // 제목 · 부제는 그대로.
      expect(find.text('인증 코드를 입력해요'), findsOneWidget);
    });

    testWidgets('첫 줄 14/600 error + circle-alert 14, 둘째 줄 14/400 body 줄높이 1.5 · 폭 312 · 위 4 · 왼쪽 18', (tester) async {
      await pumpTaken(tester, 'kakao', mine: 'google');

      final firstStyle = tester.widget<Text>(find.text(first)).style!;
      expect((firstStyle.fontSize, firstStyle.fontWeight, firstStyle.color), (14, FontWeight.w600, AppColors.error));
      final alert = tester.widget<Icon>(find.byIcon(AppIcons.circleAlert));
      expect((alert.size, alert.color), (14, AppColors.error));
      final secondStyle = tester.widget<Text>(find.text(second)).style!;
      expect((secondStyle.fontSize, secondStyle.fontWeight, secondStyle.color, secondStyle.height),
          (14, FontWeight.w400, AppColors.body, 1.5));
      final firstRow = tester.getRect(find.ancestor(of: find.text(first), matching: find.byType(Row)).first);
      final secondBox = tester.getRect(find.ancestor(of: find.text(second), matching: find.byType(Padding)).first);
      expect((secondBox.left, secondBox.width), (24, 312));
      expect(secondBox.top, firstRow.bottom);
      expect(tester.getTopLeft(find.text(second)), Offset(24 + 18, firstRow.bottom + 4));
    });

    testWidgets('주 단추 312×52 는 아래에 붙고, 보조 단추 312×48 이 8 아래, 그 밑 28', (tester) async {
      await pumpTaken(tester, 'kakao', mine: 'google');

      final primary = tester.getRect(find.widgetWithText(ElevatedButton, '카카오로 다시 로그인'));
      final secondary = tester.getRect(find.widgetWithText(InkWell, '다른 학교 메일 입력'));
      expect((primary.left, primary.width, primary.height), (24, 312, 52));
      expect((secondary.left, secondary.width, secondary.height), (24, 312, 48));
      expect(secondary.top, primary.bottom + 8);
      expect(secondary.bottom, 780 - 28);
    });

    testWidgets('"카카오로 다시 로그인" 을 누르면 안내를 남기고 로그아웃한다 — 409 만으로는 로그아웃하지 않는다', (tester) async {
      await pumpTaken(tester, 'kakao', mine: 'google');
      expect(signedOut, isEmpty);

      await tester.tap(find.text('카카오로 다시 로그인'));
      await tester.pump();

      expect(signedOut, ['signOut']);
      expect(LoginNotice.take()?.message, '이 학교 메일은 카카오로 가입돼 있어요. 카카오로 로그인해 주세요');
    });

    testWidgets('같은 소셜이 쥔 다른 계정이면 빌려 쓰기 두 줄 + "다른 학교 메일 입력" 만(다시 로그인 없음)', (tester) async {
      await pumpTaken(tester, 'kakao', mine: 'kakao');

      expect(find.text('이미 가입된 학교 메일이에요'), findsOneWidget);
      expect(find.text('한 학교 메일로는 계정 하나만 만들 수 있어요'), findsOneWidget);
      expect(find.textContaining('다시 로그인'), findsNothing);
      expect(find.text('다른 학교 메일 입력'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('확인'), findsNothing);
      expect(tester.getRect(find.widgetWithText(InkWell, '다른 학교 메일 입력')).bottom, 780 - 28);
    });

    testWidgets('옛 이메일 가입자가 쥐면 지금 문구 · 배치 그대로(코드 칸 · 확인 · 다른 학교 메일 입력)', (tester) async {
      await pumpTaken(tester, 'email', mine: 'kakao');

      expect(find.text(SchoolEmailTakenFailure.takenByEmailAccountMessage), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
      expect(find.text('다른 학교 메일 입력'), findsOneWidget);
      expect(find.textContaining('다시 로그인'), findsNothing);
    });

    for (final scale in [1.5, 2.0]) {
      testWidgets('글자 $scale배에서도 넘치지 않고 두 단추를 누를 수 있다', (tester) async {
        await pumpTaken(tester, 'kakao', mine: 'google', textScale: scale);

        expect(tester.takeException(), isNull);
        for (final label in ['카카오로 다시 로그인', '다른 학교 메일 입력']) {
          await tester.ensureVisible(find.text(label));
          await tester.pump();
          expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
        }
        final paragraph = tester.renderObject<RenderParagraph>(find.text(second));
        expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5));
      });
    }
  });

  testWidgets('서버가 인증을 못 마치면 다시 하라는 임시 문구를 보여준다', (tester) async {
    final repository = FakeSchoolEmailRepository()
      ..nextCompleteResult = const FailureResult(SchoolEmailIncompleteFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    await tester.tap(find.text('확인'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요'), findsOneWidget);
  });
  // 사용자 10-16 "Node ID: VuiDi 여기 인증코드 아래에 안내문 하나 넣어줘 스팸함도 확인 해달라고" — pen HintLine `MOmaZ`(04-2 설명 줄과 같은 부품).
  group('스팸함 안내 줄(pen VuiDi · 오류 Vn6w4)', () {
    void phone(WidgetTester tester, [Size size = const Size(360, 740)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Rect expiryRow(WidgetTester tester) =>
        tester.getRect(find.ancestor(of: find.textContaining('뒤에 만료돼요'), matching: find.byType(Row)).first);

    testWidgets('입력칸 바로 아래 8 에 파란 안내 아이콘 줄, 그 아래 16 에 만료 줄 → 메일 다시 받기 · 확인 버튼은 아래 고정', (tester) async {
      phone(tester);
      await pumpScreen(tester);

      final hint = find.byType(HintLine);
      expect(tester.widget<HintLine>(hint).text, verifyCodeSpamHint);
      expect(verifyCodeSpamHint, '메일이 보이지 않으면 스팸함도 확인해 주세요.');
      expect(tester.getRect(hint).top, tester.getRect(find.byType(TextField)).bottom + 8);
      expect(expiryRow(tester).top, tester.getRect(hint).bottom + 16);
      expect(tester.getRect(hint).left, 24);
      expect(tester.getRect(find.widgetWithText(ElevatedButton, '확인')).bottom, 740 - 28);
    });

    testWidgets('코드가 틀리면 입력칸 → 오류 문구 → 8 → 안내 → 만료 줄', (tester) async {
      phone(tester);
      final repository = FakeSchoolEmailRepository()..nextVerifyCodeResult = const FailureResult(WrongCodeFailure());
      await pumpScreen(tester, repository: repository);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.tap(find.text('확인'));
      await tester.pump(const Duration(milliseconds: 1));

      final error = tester.getRect(
        find.ancestor(of: find.text('코드가 맞지 않아요. 다시 확인해 주세요.'), matching: find.byType(Row)).first,
      );
      final hint = tester.getRect(find.byType(HintLine));
      expect(error.top, greaterThan(tester.getRect(find.byType(TextField)).bottom));
      expect(hint.top, error.bottom + 8);
      expect(expiryRow(tester).top, hint.bottom + 16);
      expect(tester.getRect(find.widgetWithText(ElevatedButton, '확인')).bottom, 740 - 28);
    });

    for (final scale in [1.5, 2.0]) {
      for (final size in [const Size(360, 740), const Size(320, 568)]) {
        testWidgets('글자 $scale배 · ${size.width.toInt()}×${size.height.toInt()} 에서 넘치지 않고 안내 글이 잘리지 않는다', (tester) async {
          phone(tester, size);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpScreen(tester);

          expect(tester.takeException(), isNull);
          final paragraph = tester.renderObject<RenderParagraph>(find.text(verifyCodeSpamHint));
          expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5));
          // 확인 버튼은 글자를 키워도 화면 안에서 눌린다(넘치면 같이 스크롤된다).
          await tester.ensureVisible(find.widgetWithText(ElevatedButton, '확인'));
          await tester.pump();
          expect(find.widgetWithText(ElevatedButton, '확인').hitTestable(), findsOneWidget);
        });
      }
    }
  });

  group('다른 학교 메일 입력(지시문 13 A-4)', () {
    Future<FakeSchoolEmailRepository> pumpWithRouter(WidgetTester tester, Failure failure) async {
      final repository = FakeSchoolEmailRepository()..nextCompleteResult = FailureResult(failure);
      final container = ProviderContainer(
        overrides: [
          schoolEmailRepositoryProvider.overrideWithValue(repository),
          verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.verifyCode,
        routes: [
          GoRoute(path: AppRoutes.login, builder: (context, state) => const Scaffold(body: Text('02 학교 메일 입력'))),
          GoRoute(path: AppRoutes.verifyCode, builder: (context, state) => VerifyCodeScreen(email: email)),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('확인'));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      return repository;
    }

    testWidgets('409 면 오류 문구 아래에 02 로그아웃 줄과 같은 모양(48 · 14/600 muted)으로 보인다', (tester) async {
      await pumpWithRouter(tester, const SchoolEmailTakenFailure('서버 문구', 'kakao'));

      final button = find.widgetWithText(InkWell, '다른 학교 메일 입력');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, 48);
      expect(tester.getTopLeft(button).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.text('카카오로 로그인해 주세요')).dy));
      final label = tester.widget<Text>(find.text('다른 학교 메일 입력'));
      expect(label.style!.fontSize, 14);
      expect(label.style!.fontWeight, FontWeight.w600);
      expect(label.style!.color, AppColors.muted);
    });

    testWidgets('422 · 미확인이어도 보인다', (tester) async {
      await pumpWithRouter(tester, const SchoolEmailRejectedFailure('등록되지 않은 학교 메일이에요'));
      expect(find.text('다른 학교 메일 입력'), findsOneWidget);

      await pumpWithRouter(tester, const SchoolEmailNotConfirmedFailure());
      expect(find.text('다른 학교 메일 입력'), findsOneWidget);
    });

    testWidgets('잠시 뒤 다시(네트워크 · 503)에는 보이지 않는다', (tester) async {
      await pumpWithRouter(tester, const SchoolEmailIncompleteFailure());

      expect(find.text('다른 학교 메일 입력'), findsNothing);
    });

    testWidgets('누르면 임시 연결을 비우고 02 로 간다', (tester) async {
      final repository = await pumpWithRouter(tester, const SchoolEmailTakenFailure('서버 문구', 'google'));

      await tester.tap(find.text('다른 학교 메일 입력'));
      await tester.pump();
      await tester.pump();

      expect(repository.calls.last, 'discard');
      expect(find.text('02 학교 메일 입력'), findsOneWidget);
    });
  });
}

/// 코드 확인 답을 [answer] 가 끝날 때까지 붙잡는다 — "확인 중" 상태를 시험한다.
class _HeldVerifyRepository extends FakeSchoolEmailRepository {
  final answer = Completer<Result<String>>();

  @override
  Future<Result<String>> verifyCode(UniversityEmail email, VerificationCode code) {
    calls.add('verifyCode');
    return answer.future;
  }
}
