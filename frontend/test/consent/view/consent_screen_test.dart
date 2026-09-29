import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_checkbox.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/consent_repository_provider.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/consent/view/consent_row.dart';
import 'package:campus_mate/consent/view/consent_screen.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';
import '../../profile/model/fake_onboarding_repository.dart';
import '../model/fake_consent_repository.dart';

const _title = '서비스 이용을 위해 동의해 주세요';
const _description = '필수 항목에 모두 동의하면 시작할 수 있어요.\n마케팅 알림은 선택이에요.';

void main() {
  late FakeConsentRepository consents;
  late List<Uri> opened;
  late Future<bool> Function(Uri) openUrl;
  late int signOutCalls;

  setUp(() {
    consents = FakeConsentRepository();
    opened = [];
    openUrl = (uri) async {
      opened.add(uri);
      return true;
    };
    signOutCalls = 0;
  });

  /// pen 02-c 는 360×780 이다. 배율 1 이라 논리 크기가 pen 값과 같다.
  Future<void> pump(
    WidgetTester tester, {
    VerificationGate gate = VerificationGate.needsConsent,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateRepository = FakeVerificationGateRepository()..nextResult = Success(gate);
    final container = ProviderContainer(
      overrides: [
        consentRepositoryProvider.overrideWithValue(consents),
        verificationGateRepositoryProvider.overrideWithValue(gateRepository),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        openUrlProvider.overrideWithValue((uri) => openUrl(uri)),
        signOutProvider.overrideWithValue(() async => signOutCalls++),
      ],
    );
    addTearDown(container.dispose);
    await container.read(verificationGateListenableProvider).refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ConsentScreen(),
        ),
      ),
    );
  }

  Finder row(String label) => find.ancestor(of: find.text(label), matching: find.byType(ConsentRow));
  Finder itemRow(ConsentItem item) => row(item.label);
  bool checkedIn(Finder row) =>
      (find.descendant(of: row, matching: find.byType(AppCheckbox)).evaluate().single.widget as AppCheckbox).checked;
  Finder viewIn(Finder row) => find.descendant(of: row, matching: find.text('보기'));
  AppButton agreeButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.widgetWithText(AppButton, '동의하고 계속하기'));

  Future<void> checkRequired(WidgetTester tester) async {
    for (final item in ConsentItem.values.where((item) => item.isRequired)) {
      await tester.tap(find.text(item.label));
    }
    await tester.pump();
  }

  testWidgets('pen 02-c 문구가 그대로 보인다', (tester) async {
    await pump(tester);

    expect(find.text('약관 동의'), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_description), findsOneWidget);
    expect(find.text('전체 동의'), findsOneWidget);
    for (final item in ConsentItem.values) {
      expect(find.text(item.label), findsOneWidget, reason: item.name);
    }
    expect(find.text('필수'), findsNWidgets(4));
    expect(find.text('선택'), findsOneWidget);
    expect(find.text('보기'), findsNWidgets(4));
    expect(find.text('동의하고 계속하기'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('재동의면 제목 · 설명만 바뀐다(02-c-4)', (tester) async {
    await pump(tester, gate: VerificationGate.needsConsentRenewal);

    expect(find.text('약관이 바뀌었어요'), findsOneWidget);
    expect(find.text('바뀐 내용을 확인하고 다시 동의해 주세요.'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(find.text('약관 동의'), findsOneWidget);
    expect(find.text('보기'), findsNWidgets(4));
  });

  testWidgets('줄을 누르면 체크가 바뀌고, 필수를 다 켜야 버튼이 켜진다', (tester) async {
    await pump(tester);
    expect(agreeButton(tester).onPressed, isNull);

    await tester.tap(find.text(ConsentItem.terms.label));
    await tester.pump();
    expect(checkedIn(itemRow(ConsentItem.terms)), isTrue);
    expect(agreeButton(tester).onPressed, isNull);

    await tester.tap(find.text(ConsentItem.terms.label));
    await checkRequired(tester);
    expect(checkedIn(itemRow(ConsentItem.marketing)), isFalse);
    expect(checkedIn(row('전체 동의')), isFalse);
    expect(agreeButton(tester).onPressed, isNotNull);
  });

  testWidgets('전체 동의를 누르면 모두 켜지고 다시 누르면 모두 꺼진다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('전체 동의'));
    await tester.pump();
    for (final item in ConsentItem.values) {
      expect(checkedIn(itemRow(item)), isTrue, reason: item.name);
    }
    expect(checkedIn(row('전체 동의')), isTrue);

    await tester.tap(find.text('전체 동의'));
    await tester.pump();
    expect(ConsentItem.values.where((item) => checkedIn(itemRow(item))), isEmpty);
  });

  testWidgets('보기는 그 줄의 노션 항을 한 번 연다 — 체크는 바뀌지 않는다', (tester) async {
    await pump(tester);

    for (final item in ConsentItem.values.where((item) => item.link != null)) {
      await tester.tap(viewIn(itemRow(item)));
      await tester.pump();
    }

    expect(opened, [for (final item in ConsentItem.values) ?item.link]);
    expect(ConsentItem.values.where((item) => checkedIn(itemRow(item))), isEmpty);
    expect(viewIn(itemRow(ConsentItem.marketing)), findsNothing);
  });

  testWidgets('브라우저를 못 열면 안내를 띄우고 화면에 남는다', (tester) async {
    openUrl = (_) async => false;
    await pump(tester);

    await tester.tap(viewIn(itemRow(ConsentItem.terms)));
    await tester.pump();
    expect(find.widgetWithText(AppToast, const UnknownFailure().toDisplayMessage()), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AppToast), findsNothing);

    openUrl = (_) async => throw Exception('no browser');
    await tester.tap(viewIn(itemRow(ConsentItem.privacy)));
    await tester.pump();
    expect(find.widgetWithText(AppToast, const UnknownFailure().toDisplayMessage()), findsOneWidget);
    expect(find.byType(ConsentScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('동의하고 계속하기는 켠 줄을 보낸다', (tester) async {
    await pump(tester);
    await checkRequired(tester);
    await tester.tap(find.text(ConsentItem.marketing.label));
    await tester.pump();

    await tester.tap(find.text('동의하고 계속하기'));
    await tester.pumpAndSettle();

    expect(consents.submitted, [ConsentItem.values.toSet()]);
  });

  testWidgets('저장이 실패하면 안내를 띄우고 다시 누를 수 있다', (tester) async {
    consents.nextResult = const FailureResult(NetworkFailure());
    await pump(tester);
    await checkRequired(tester);

    await tester.tap(find.text('동의하고 계속하기'));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(AppToast, const NetworkFailure().toDisplayMessage()), findsOneWidget);
    expect(agreeButton(tester).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('로그아웃은 16g 시트로 한 번 더 묻고, 확인하면 로그아웃을 한 번 부른다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('로그아웃할까요?'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(SafetyConfirmSheet), matching: find.text('로그아웃')));
    await tester.pumpAndSettle();

    expect(signOutCalls, 1);
  });

  testWidgets('관문이라 시스템 뒤로가기로 빠져나가지 않는다', (tester) async {
    await pump(tester);

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
  });

  testWidgets('글자 2배에서도 넘치지 않고, 아래 버튼은 제자리에 있다', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.widgetWithText(InkWell, '로그아웃')).bottom, 780 - 16);
    // 본문은 스크롤된다 — 맨 아래 줄까지 끌어올릴 수 있다.
    await tester.dragUntilVisible(
      find.text(ConsentItem.marketing.label),
      find.byType(SingleChildScrollView),
      const Offset(0, -80),
    );
    expect(tester.takeException(), isNull);
  });

  group('pen 값(02-c woJzd · ConsentRow rmMvJ/jFMyA)', () {
    testWidgets('앱바 KH1hX — 높이 56 · 뒤로 없음 · 제목 20/700 ink', (tester) async {
      await pump(tester);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.toolbarHeight, 56);
      expect(appBar.automaticallyImplyLeading, isFalse);
      expect(find.byType(BackButton), findsNothing);
      expect(tester.widget<Text>(find.text('약관 동의')).style, AppTypography.navTitle.copyWith(color: AppColors.ink));
    });

    testWidgets('본문 [8,16,0,16] · 제목 24/700 · 설명 16/400 body · 간격 8 · 24', (tester) async {
      await pump(tester);

      final title = tester.getRect(find.text(_title));
      final description = tester.getRect(find.text(_description));
      final allAgree = tester.getRect(row('전체 동의'));
      expect(title.left, 16);
      expect(title.top, 56 + 8);
      expect(description.top, title.bottom + 8);
      expect(allAgree.top, closeTo(description.bottom + 24, 0.01));
      expect(allAgree.width, 328);
      expect(tester.widget<Text>(find.text(_title)).style, AppTypography.headline.copyWith(color: AppColors.ink));
      expect(tester.widget<Text>(find.text(_description)).style, AppTypography.body.copyWith(color: AppColors.body));
    });

    testWidgets('전체 동의 — 뱃지 · 보기 없음 · 17/600 · 아래 구분선 #EBEBEB 1', (tester) async {
      await pump(tester);

      final allAgree = row('전체 동의');
      expect(find.descendant(of: allAgree, matching: find.text('필수')), findsNothing);
      expect(viewIn(allAgree), findsNothing);
      expect(tester.widget<Text>(find.text('전체 동의')).style, AppTypography.subtitle.copyWith(color: AppColors.ink));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, AppColors.hairlineSoft);
      expect(divider.thickness, 1);
      expect(tester.getRect(find.byType(Divider)).top, tester.getRect(allAgree).bottom);
      expect(tester.getRect(find.byType(Divider)).height, 1);
      expect(tester.getRect(itemRow(ConsentItem.terms)).top, tester.getRect(find.byType(Divider)).bottom);
    });

    testWidgets('항목 줄 — 한 줄 50 · 체크 · 뱃지 · 글 사이 12 · 보기와 8', (tester) async {
      await pump(tester);

      final terms = itemRow(ConsentItem.terms);
      // 글 16 × 1.6 = 25.6 + 위아래 12 — pen 렌더 50 은 반올림이다.
      expect(tester.getRect(terms).height, closeTo(50, 0.5));
      final checkbox = tester.getRect(find.descendant(of: terms, matching: find.byType(AppCheckbox)));
      final badge = tester.getRect(find.descendant(of: terms, matching: find.text('필수')));
      final label = tester.getRect(find.text(ConsentItem.terms.label));
      expect(checkbox.left, 16);
      expect(checkbox.size, const Size(24, 24));
      // 뱃지는 알약(글자 좌우 6) — 글자 칸 기준으로 체크와 12 + 6.
      expect(badge.left, checkbox.right + 12 + 6);
      expect(label.left, badge.right + 6 + 12);
      final view = tester.getRect(find.ancestor(of: viewIn(terms), matching: find.byType(InkWell)).first);
      final toggle =
          tester.getRect(find.ancestor(of: find.text(ConsentItem.terms.label), matching: find.byType(InkWell)).first);
      expect(view.left, toggle.right + 8);
      expect(view.right, 360 - 16);
      expect(view.height, 48);
    });

    testWidgets('글은 16/400 lh 1.6 ink · 국외 이전은 두 줄', (tester) async {
      await pump(tester);

      for (final item in ConsentItem.values) {
        expect(tester.widget<Text>(find.text(item.label)).style, AppTypography.body.copyWith(color: AppColors.ink),
            reason: item.name);
      }
      // pen 처럼 줄을 직접 바꾼 두 줄이다 — 한 줄 높이의 두 배(글꼴이 줄마다 반올림해 25.6 이 아니라 26).
      final oneLine = tester.getRect(find.text(ConsentItem.terms.label)).height;
      expect(tester.getRect(find.text(ConsentItem.overseasTransfer.label)).height, oneLine * 2);
    });

    testWidgets('체크 칸 zlg4q · ORl5o — 24 · 모서리 6 · 꺼짐 흰 바탕 #767676 1.5 · 켜짐 primary + 체크 16', (tester) async {
      await pump(tester);
      BoxDecoration box() => tester
          .widget<Container>(find.descendant(of: find.byType(AppCheckbox).first, matching: find.byType(Container)))
          .decoration! as BoxDecoration;

      expect(box().color, AppColors.canvas);
      expect(box().borderRadius, BorderRadius.circular(6));
      expect(box().border, Border.all(color: AppColors.outline, width: 1.5));

      await tester.tap(find.text('전체 동의'));
      await tester.pump();
      expect(box().color, AppColors.primary);
      expect(box().border, isNull);
      final check = tester.widget<Icon>(find.descendant(of: find.byType(AppCheckbox).first, matching: find.byType(Icon)));
      expect(check.icon, AppIcons.check);
      expect(check.size, 16);
      expect(check.color, AppColors.onPrimary);
    });

    testWidgets('뱃지 Aioxz — 필수 #FFF0F2/#C4224B · 선택 #F2F2F2/#6A6A6A · 11/700 · 높이 20', (tester) async {
      await pump(tester);
      BoxDecoration pill(String text) =>
          tester.widget<Container>(find.ancestor(of: find.text(text).first, matching: find.byType(Container)).first)
              .decoration! as BoxDecoration;
      TextStyle style(String text) => tester.widget<Text>(find.text(text).first).style!;

      expect(pill('필수').color, AppColors.primaryWash);
      expect(style('필수').color, AppColors.primaryText);
      expect(pill('선택').color, AppColors.surfaceStrong);
      expect(style('선택').color, AppColors.muted);
      expect(pill('필수').borderRadius, BorderRadius.circular(AppRadius.pill));
      expect(style('필수').fontSize, 11);
      expect(style('필수').fontWeight, FontWeight.w700);
      expect(
        tester.getRect(find.ancestor(of: find.text('필수').first, matching: find.byType(Container)).first).height,
        closeTo(20, 0.01),
      );
    });

    testWidgets('보기 — 14/400 muted · 쉐브론 20 muted · 왼쪽 8 · 간격 2', (tester) async {
      await pump(tester);
      final terms = itemRow(ConsentItem.terms);
      final view = tester.getRect(find.ancestor(of: viewIn(terms), matching: find.byType(InkWell)).first);
      final text = tester.getRect(viewIn(terms));
      final chevron = find.descendant(of: terms, matching: find.byIcon(AppIcons.chevronRight));

      expect(tester.widget<Text>(viewIn(terms)).style, AppTypography.bodySmall.copyWith(color: AppColors.muted));
      expect(text.left, view.left + 8);
      expect(tester.getRect(chevron).left, text.right + 2);
      expect(tester.widget<Icon>(chevron).size, 20);
      expect(tester.widget<Icon>(chevron).color, AppColors.muted);
    });

    testWidgets('아래 묶음 [0,16,16,16] · 버튼 56 · 간격 4 · 로그아웃 48 14/600 muted', (tester) async {
      await pump(tester);
      final button = tester.getRect(find.byType(AppButton));
      final logout = tester.getRect(find.widgetWithText(InkWell, '로그아웃'));

      expect(button.left, 16);
      expect(button.width, 328);
      expect(button.height, 56);
      expect(logout.top, button.bottom + 4);
      expect(logout.height, 48);
      expect(logout.bottom, 780 - 16);
      expect(logout.width, 328);
      expect(
        tester.widget<Text>(find.text('로그아웃')).style,
        AppTypography.labelSmall.copyWith(color: AppColors.muted, height: 20 / 14),
      );
    });

    testWidgets('안내 토스트는 버튼 위 12 · 가운데(편차 2)', (tester) async {
      openUrl = (_) async => false;
      await pump(tester);

      await tester.tap(viewIn(itemRow(ConsentItem.terms)));
      await tester.pump();

      final toast = tester.getRect(find.byType(AppToast));
      expect(toast.bottom, tester.getRect(find.byType(AppButton)).top - 12);
      expect(toast.center.dx, 180);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
