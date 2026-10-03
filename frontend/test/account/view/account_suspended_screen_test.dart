import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_account_repository.dart';

void main() {
  late int signOutCalls;
  late FakeAccountRepository account;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    signOutCalls = 0;
    account = FakeAccountRepository();
    container = ProviderContainer(
      overrides: [
        signOutProvider.overrideWithValue(() async => signOutCalls++),
        accountRepositoryProvider.overrideWithValue(account),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: AccountSuspendedScreen())),
    );
  }

  testWidgets('pen e7QaDh 글자를 그대로 보여준다(값표 7절)', (tester) async {
    await pump(tester);

    expect(find.text('이용이 제한된 계정이에요'), findsOneWidget);
    expect(
      find.text('누적된 신고 내용을 검토한 결과, 이용이 제한되었어요. 부적절한 이용이 반복되면 계정이 삭제될 수 있어요.'),
      findsOneWidget,
    );
    expect(find.text('제한 내용이 궁금하거나 잘못된 것 같다면 아래 메일로 알려 주세요.'), findsOneWidget);
    expect(find.text('문의 메일'), findsOneWidget);
    expect(find.text('가입한 학교 메일 주소를 함께 적어 주시면 더 빨리 확인할 수 있어요.'), findsOneWidget);
    expect(find.byIcon(AppIcons.mail), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('문의 메일 주소가 보인다', (tester) async {
    await pump(tester);

    expect(find.text('appmailerl4538@gmail.com'), findsOneWidget);
    expect(supportEmail, 'appmailerl4538@gmail.com');
  });

  testWidgets('슬픈 마스코트 120(pen U7msJ)', (tester) async {
    await pump(tester);

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/images/mascot-female-sad.png');
    expect(tester.getSize(find.byType(Image)), const Size(120, 120));
  });

  testWidgets('"로그아웃"을 누르면 signOutProvider 를 한 번 부른다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pump();

    expect(signOutCalls, 1);
  });

  testWidgets('로그아웃은 하단 주색 AppButton 이다(pen zPgpR)', (tester) async {
    await pump(tester);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.variant, AppButtonVariant.primary);
    // 아래로 간격 20 · 탈퇴하기 44 · 화면 아래 여백 40(pen HG0d7).
    expect(tester.getRect(find.byType(AppButton)).bottom, 600 - 40 - 44 - 20);
  });

  testWidgets('로그아웃 아래 탈퇴하기 글자 버튼(pen r3KNbz 312×44 · 14/700 muted)', (tester) async {
    await pump(tester);

    final withdraw = find.ancestor(of: find.text('탈퇴하기'), matching: find.byType(TextButton));
    expect(tester.getRect(withdraw).bottom, 600 - 40);
    expect(tester.getRect(withdraw).top - tester.getRect(find.byType(AppButton)).bottom, 20);
    expect(tester.getSize(withdraw).width, tester.getSize(find.byType(AppButton)).width);
    expect(tester.getSize(withdraw).height, 44);
    final style = tester.widget<Text>(find.text('탈퇴하기')).style!;
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.color, AppColors.muted);
    expect(style.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('탈퇴하기는 일시중지 제안 없이 정지 중 탈퇴 시트(pen XHGTs) 한 장을 연다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(find.byType(WithdrawFirstSheet), findsNothing);
    expect(find.text('정지 중에 탈퇴할까요?'), findsOneWidget);
    expect(account.withdrawCalls, 0);

    await tester.tap(find.descendant(of: find.byType(WithdrawFinalSheet), matching: find.text('정말 영구 삭제')));
    await tester.pumpAndSettle();

    expect(account.withdrawCalls, 1);
    // 로그아웃은 main.dart 리스너 한 곳이 한다 — 화면은 상태만 바꾼다.
    expect(container.read(accountStatusListenableProvider).value, AccountStatus.withdrawn);
    expect(signOutCalls, 0);
  });

  testWidgets('앱바 · 하단 내비가 없다', (tester) async {
    await pump(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(AppBottomNav), findsNothing);
  });

  testWidgets('360×780 · 글자 배율 2.0 에서도 넘치지 않고 탈퇴하기까지 보인다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('탈퇴하기')).bottom, lessThanOrEqualTo(780));
  });
}
