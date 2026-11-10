import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_account_email_provider.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_repository_provider.dart';
import 'package:campus_mate/inquiry/view/inquiry_screen.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/repository/fake_inquiry_repository.dart';

void main() {
  late FakeInquiryRepository repository;

  /// pen 보드와 같은 360×780 화면. 문의 화면은 이전 화면 위에 push 로 열린다(설정 · FAQ 가 연다) — 보낸 뒤 돌아갈 곳이 있어야 한다.
  Future<void> open(WidgetTester tester, {String? accountEmail, double scale = 1}) async {
    repository = FakeInquiryRepository();
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => context.push(AppRoutes.inquiry), child: const Text('이전 화면')),
            ),
          ),
        ),
        GoRoute(path: AppRoutes.inquiry, builder: (context, state) => const InquiryScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inquiryRepositoryProvider.overrideWithValue(repository),
          inquiryAccountEmailProvider.overrideWithValue(accountEmail),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('이전 화면'));
    await tester.pumpAndSettle();
  }

  Finder bodyField() => find.byKey(InquiryScreen.bodyKey);
  Finder emailField() => find.byKey(InquiryScreen.replyEmailKey);
  AppButton submitButton(WidgetTester tester) => tester.widget<AppButton>(find.widgetWithText(AppButton, '보내기'));

  Future<void> pickReason(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(InquiryScreen.reasonSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.tap(find.text('선택하기'));
    await tester.pumpAndSettle();
  }

  Future<void> fillAll(WidgetTester tester) async {
    await pickReason(tester, '결제 · 하트');
    await tester.enterText(bodyField(), '하트를 결제했는데 반영되지 않았어요');
    await tester.enterText(emailField(), 'hello@example.com');
    await tester.pump();
  }

  group('빈 화면 (pen 21a o8YoF)', () {
    testWidgets('앱바: 뒤로 화살표 22 는 가운데 (32,28), 제목 "문의하기" 는 x60', (tester) async {
      await open(tester);

      final arrow = find.byIcon(AppIcons.arrowLeft);
      expect(tester.getCenter(arrow), const Offset(32, 28));
      expect(tester.getSize(arrow), const Size(22, 22));
      expect(tester.getSize(find.ancestor(of: arrow, matching: find.byType(IconButton))).width, 48);
      expect(tester.getTopLeft(find.text('문의하기')).dx, 60);
    });

    testWidgets('안내 줄: 파란 안내 아이콘과 두 줄 안내 글이 (16,72) 에서 시작한다', (tester) async {
      await open(tester);

      final hint = find.text('궁금하거나 불편한 점을 알려 주세요. 적어 주신 메일로 답장을 드려요.');
      expect(hint, findsOneWidget);
      expect(tester.getTopLeft(hint).dx, 16 + 18 + 8);
      expect(tester.getTopLeft(hint).dy, 72);
      expect(tester.getSize(hint).height, closeTo(44, 1));
    });

    testWidgets('사유 칸: 328×52 가 (16,163), 안내 글 "사유를 선택해 주세요" 는 muted, 셰브런 20', (tester) async {
      await open(tester);

      expect(find.text('문의 사유'), findsOneWidget);
      final select = find.byKey(InquiryScreen.reasonSelectKey);
      expect(tester.getTopLeft(select), const Offset(16, 163));
      expect(tester.getSize(select), const Size(328, 52));
      final placeholder = tester.widget<Text>(find.text('사유를 선택해 주세요'));
      expect(placeholder.style!.color, AppColors.muted);
      expect(placeholder.style!.fontSize, 16);
      expect(tester.getSize(find.byIcon(AppIcons.chevronDown)), const Size(20, 20));
    });

    testWidgets('내용 칸: 328×160 이 (16,262), 안내 글 14 muted, 카운터 "0 / 1000" 12 muted', (tester) async {
      await open(tester);

      expect(find.text('내용'), findsOneWidget);
      final box = find.byKey(InquiryScreen.bodyBoxKey);
      expect(tester.getTopLeft(box), const Offset(16, 262));
      expect(tester.getSize(box), const Size(328, 160));
      final field = tester.widget<TextField>(bodyField());
      expect(field.decoration!.hintText, '문의하실 내용을 적어 주세요.');
      expect(field.decoration!.hintStyle!.color, AppColors.muted);
      final counter = tester.widget<Text>(find.text('0 / 1000'));
      expect(counter.style!.fontSize, 12);
      expect(counter.style!.color, AppColors.muted);
    });

    testWidgets('메일 칸: 328×52 가 (16,469), 앞에 메일 아이콘 20, 안내 "예) name@example.com", 체크는 숨김', (tester) async {
      await open(tester);

      expect(find.text('답장 받을 메일'), findsOneWidget);
      final input = find.byKey(InquiryScreen.replyEmailBoxKey);
      expect(tester.getTopLeft(input), const Offset(16, 469));
      expect(tester.getSize(input), const Size(328, 52));
      expect(tester.getSize(find.byIcon(AppIcons.mail)), const Size(20, 20));
      expect(tester.widget<TextField>(emailField()).decoration!.hintText, '예) name@example.com');
      expect(find.byIcon(AppIcons.check), findsNothing);
    });

    testWidgets('보내기: 328×52 가 아래 바 (16,708) 에 있고 꺼져 있다', (tester) async {
      await open(tester);

      final button = find.widgetWithText(AppButton, '보내기');
      expect(tester.getTopLeft(button), const Offset(16, 708));
      expect(tester.getSize(button), const Size(328, 52));
      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('계정 메일을 알면 메일 칸이 미리 채워지고 체크가 켜진다', (tester) async {
      await open(tester, accountEmail: 'me@gmail.com');

      expect(find.text('me@gmail.com'), findsOneWidget);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });
  });

  group('사유 고르기 (pen 21b P15T9)', () {
    testWidgets('사유 칸을 누르면 시트가 열리고, 고른 뒤 선택하기로 닫으면 칸에 글자가 ink 색으로 들어간다', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(InquiryScreen.reasonSelectKey));
      await tester.pumpAndSettle();
      expect(find.byType(SafetySheet), findsOneWidget);
      expect(find.text('무엇을 문의할까요?'), findsOneWidget);

      await tester.tap(find.text('결제 · 하트'));
      await tester.pump();
      await tester.tap(find.text('선택하기'));
      await tester.pumpAndSettle();

      expect(find.byType(SafetySheet), findsNothing);
      final value = tester.widget<Text>(
        find.descendant(of: find.byKey(InquiryScreen.reasonSelectKey), matching: find.byType(Text)),
      );
      expect(value.data, '결제 · 하트');
      expect(value.style!.color, AppColors.ink);
    });

    testWidgets('취소하면 사유는 그대로 비어 있다', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(InquiryScreen.reasonSelectKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('앱 오류'));
      await tester.pump();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.text('사유를 선택해 주세요'), findsOneWidget);
    });
  });

  group('채우기 (pen 21c unMlh)', () {
    testWidgets('내용을 쓰면 카운터가 따라가고 1000자에서 멈춘다 — 서버 상한과 같은 코드포인트로 센다', (tester) async {
      await open(tester);

      // pen 21c 예시 글 — 카운터 "34 / 1000".
      await tester.enterText(bodyField(), '하트를 결제했는데 잔액에 반영되지 않았어요. 확인 부탁드려요.');
      await tester.pump();
      expect(find.text('34 / 1000'), findsOneWidget);

      await tester.enterText(bodyField(), '가' * 1200);
      await tester.pump();
      expect(find.text('1000 / 1000'), findsOneWidget);
      expect(tester.widget<TextField>(bodyField()).controller!.text.runes.length, 1000);
    });

    testWidgets('사유 · 내용 · 메일을 다 채우면 보내기가 켜지고 메일 칸 오른쪽에 체크가 뜬다', (tester) async {
      await open(tester);
      await fillAll(tester);

      expect(submitButton(tester).onPressed, isNotNull);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });

    testWidgets('사유만 비어 있어도 보내기는 꺼져 있다', (tester) async {
      await open(tester);
      await tester.enterText(bodyField(), '내용');
      await tester.enterText(emailField(), 'hello@example.com');
      await tester.pump();

      expect(submitButton(tester).onPressed, isNull);
    });
  });

  group('메일 형식 오류', () {
    testWidgets('쓰는 도중에는 조용하다가 칸을 벗어난 뒤에도 틀려 있으면 빨간 줄이 뜨고 보내기는 꺼져 있다', (tester) async {
      await open(tester);
      await pickReason(tester, '기타');
      await tester.enterText(bodyField(), '내용');

      await tester.enterText(emailField(), 'hello@exa');
      await tester.pump();
      expect(find.text('메일 주소 형식을 확인해 주세요'), findsNothing);

      // 다른 칸으로 옮겨 메일 칸을 벗어난다.
      await tester.tap(bodyField());
      await tester.pump();

      expect(find.text('메일 주소 형식을 확인해 주세요'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);
      expect(find.byIcon(AppIcons.check), findsNothing);
    });

    testWidgets('고쳐서 맞으면 빨간 줄이 사라진다', (tester) async {
      await open(tester);
      await tester.enterText(emailField(), 'hello@exa');
      await tester.tap(bodyField());
      await tester.pump();
      expect(find.text('메일 주소 형식을 확인해 주세요'), findsOneWidget);

      await tester.enterText(emailField(), 'hello@example.com');
      await tester.pump();

      expect(find.text('메일 주소 형식을 확인해 주세요'), findsNothing);
    });
  });

  group('보내기', () {
    testWidgets('누르면 사유 코드 · 내용 · 메일을 보내고, 이전 화면으로 돌아가 "문의를 보냈어요" 토스트가 뜬다 (pen de3Sv)', (tester) async {
      await open(tester);
      await fillAll(tester);

      await tester.tap(find.widgetWithText(AppButton, '보내기'));
      await tester.pumpAndSettle();

      expect(repository.sent, [
        (reason: InquiryReason.payment, body: '하트를 결제했는데 반영되지 않았어요', replyEmail: 'hello@example.com'),
      ]);
      expect(find.byType(InquiryScreen), findsNothing);
      expect(find.text('이전 화면'), findsOneWidget);
      expect(find.text('문의를 보냈어요'), findsOneWidget);
    });

    testWidgets('보내는 중에는 버튼이 돌고 눌러도 한 번만 간다', (tester) async {
      await open(tester);
      await fillAll(tester);
      repository.holdSend = Completer<void>();

      await tester.tap(find.widgetWithText(AppButton, '보내기'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(repository.sent, hasLength(1));

      repository.holdSend!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InquiryScreen), findsNothing);
    });

    testWidgets('429 하루 상한이면 "오늘은 더 문의할 수 없어요" 를 빨갛게 보이고 화면과 쓴 글이 남는다', (tester) async {
      await open(tester);
      await fillAll(tester);
      repository.sendResult = const FailureResult(RateLimitedFailure('서버 문구'));

      await tester.tap(find.widgetWithText(AppButton, '보내기'));
      await tester.pumpAndSettle();

      final message = tester.widget<Text>(find.text('오늘은 더 문의할 수 없어요'));
      expect(message.style!.color, AppColors.error);
      expect(find.byType(InquiryScreen), findsOneWidget);
      expect(find.text('하트를 결제했는데 반영되지 않았어요'), findsOneWidget);
      expect(find.text('문의를 보냈어요'), findsNothing);
    });

    testWidgets('연결이 끊기면 네트워크 문구를 보이고, 다시 누르면 같은 내용이 다시 간다', (tester) async {
      await open(tester);
      await fillAll(tester);
      repository.sendResult = const FailureResult(NetworkFailure());

      await tester.tap(find.widgetWithText(AppButton, '보내기'));
      await tester.pumpAndSettle();
      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);

      repository.sendResult = const Success(null);
      await tester.tap(find.widgetWithText(AppButton, '보내기'));
      await tester.pumpAndSettle();

      expect(repository.sent, hasLength(2));
      expect(find.text('문의를 보냈어요'), findsOneWidget);
    });
  });

  testWidgets('뒤로 화살표를 누르면 이전 화면으로 돌아간다', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(AppIcons.arrowLeft));
    await tester.pumpAndSettle();

    expect(find.byType(InquiryScreen), findsNothing);
    expect(find.text('이전 화면'), findsOneWidget);
  });

  testWidgets('누르는 칸은 모두 44 이상이다 — 뒤로 · 사유 칸 · 메일 칸 · 보내기', (tester) async {
    await open(tester);

    final targets = [
      find.ancestor(of: find.byIcon(AppIcons.arrowLeft), matching: find.byType(IconButton)),
      find.byKey(InquiryScreen.reasonSelectKey),
      find.byKey(InquiryScreen.replyEmailBoxKey),
      find.widgetWithText(AppButton, '보내기'),
    ];
    for (final target in targets) {
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('글자 2배 · 360 폭에서도 넘치지 않고 스크롤로 닿는다', (tester) async {
    await open(tester, scale: 2);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('보내기'), findsOneWidget);
  });
}
