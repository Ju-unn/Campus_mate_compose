import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/profile/basic/model/repository/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/basic/view/basic_info_screen.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_view_model.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../onboarding/model/repository/fake_onboarding_repository.dart';
import '../model/repository/fake_basic_info_repository.dart';

/// 04-1 휴대폰 문자 인증(pen 값표 2c — PhoneVerifyField `SKvqx` · OtpEntryRow `EqLaR` · 상태 ①~⑬)을 화면째로 본다.
/// 시계는 가짜다 — [now] 를 옮기고 같은 만큼 타이머를 돌린다.
void main() {
  late FakeBasicInfoRepository repository;
  late DateTime now;

  setUp(() {
    repository = FakeBasicInfoRepository();
    now = DateTime(2026, 6, 1, 12);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          basicInfoNowProvider.overrideWithValue(() => now),
          basicInfoRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BasicInfoScreen(),
        ),
      ),
    );
  }

  Future<void> elapse(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
  }

  /// 화면을 닫는다 — 뷰모델이 폐기되며 1초 시계도 멈춘다(남은 타이머가 있으면 testWidgets 가 끝에서 실패한다).
  Future<void> close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  Finder field(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);
  final phoneField = field('010-0000-0000');
  final codeField = field('6자리 숫자');
  Finder button(String label) => find.widgetWithText(AppButton, label);
  final sendButton = button('인증번호 받기');

  TextField textField(WidgetTester tester, Finder finder) => tester.widget<TextField>(finder);
  InputDecoration decoration(WidgetTester tester, Finder finder) => textField(tester, finder).decoration!;
  BorderSide enabledSide(WidgetTester tester, Finder finder) =>
      (decoration(tester, finder).enabledBorder! as OutlineInputBorder).borderSide;
  bool isEnabled(WidgetTester tester, Finder appButton) =>
      tester.widget<ElevatedButton>(find.descendant(of: appButton, matching: find.byType(ElevatedButton))).enabled;
  Color? textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

  /// 상태 줄(DtNAW): 표식 14 → 4 → 12/400 글자.
  void expectStatusLine(WidgetTester tester, String text, {required IconData icon, required Color color}) {
    final label = find.text(text);
    expect(label, findsOneWidget, reason: text);
    final style = tester.widget<Text>(label).style!;
    expect(style.color, color);
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.w400);
    final mark = find.byWidgetPredicate((w) => w is Icon && w.icon == icon);
    expect(mark, findsOneWidget);
    expect(tester.widget<Icon>(mark).size, 14);
    expect(tester.widget<Icon>(mark).color, color);
    expect(tester.getTopLeft(label).dx - tester.getTopRight(mark).dx, 4);
  }

  /// 번호 칸 잠김 모양(⑥ ⑩ ⑪ ⑬): #F2F2F2 · #EBEBEB 1 · 값 #3F3F3F, 입력 막힘.
  void expectPhoneLocked(WidgetTester tester) {
    expect(decoration(tester, phoneField).fillColor, AppColors.surfaceStrong);
    expect(enabledSide(tester, phoneField), const BorderSide(color: AppColors.hairlineSoft));
    expect(textField(tester, phoneField).style?.color, AppColors.body);
    expect(textField(tester, phoneField).readOnly, isTrue);
  }

  /// 번호 칸 보통 모양: #F7F7F7 · #DDDDDD 1 · 값 ink.
  void expectPhoneNormal(WidgetTester tester) {
    expect(decoration(tester, phoneField).fillColor, AppColors.surfaceSoft);
    expect(enabledSide(tester, phoneField), const BorderSide(color: AppColors.hairline));
    expect(textField(tester, phoneField).style?.color, AppColors.ink);
    expect(textField(tester, phoneField).readOnly, isFalse);
  }

  Future<void> typePhone(WidgetTester tester, [String digits = '01001352468']) async {
    await tester.enterText(phoneField, digits);
    await tester.pump();
  }

  Future<void> sendCode(WidgetTester tester) async {
    await typePhone(tester);
    await tester.tap(sendButton);
    await tester.pump();
  }

  testWidgets('① 입력 전 — 받기 회색(#E5E5E5 · #929292), 상태 줄 · 인증번호 줄 없음, 상자 52 · 라벨과 8', (tester) async {
    await pumpScreen(tester);

    expect(isEnabled(tester, sendButton), isFalse);
    final style = tester.widget<ElevatedButton>(find.descendant(of: sendButton, matching: find.byType(ElevatedButton))).style!;
    expect(style.backgroundColor?.resolve({WidgetState.disabled}), AppColors.primaryDisabled);
    expect(style.foregroundColor?.resolve({WidgetState.disabled}), AppColors.disabled);
    expect(codeField, findsNothing);
    expect(find.text('인증됐어요'), findsNothing);
    expectPhoneNormal(tester);
    expect(textField(tester, phoneField).keyboardType, TextInputType.phone);

    final box = tester.getRect(phoneField);
    expect(box.height, 52);
    expect(box.top - tester.getBottomLeft(find.text('전화번호 · 필수')).dy, 8);
    expect(decoration(tester, phoneField).hintStyle?.color, AppColors.muted);
    expect((decoration(tester, phoneField).enabledBorder! as OutlineInputBorder).borderRadius, BorderRadius.circular(12));
  });

  testWidgets('② 번호를 다 치면 받기가 분홍으로 켜지고, 상자 오른쪽 8 · 바닥 맞춤 · 높이 52 · 안쪽 16', (tester) async {
    await pumpScreen(tester);

    await typePhone(tester);

    expect(isEnabled(tester, sendButton), isTrue);
    final box = tester.getRect(phoneField);
    final send = tester.getRect(sendButton);
    expect(send.left - box.right, 8);
    expect(send.bottom, box.bottom);
    expect(send.height, 52);
    expect(tester.getTopLeft(find.text('인증번호 받기')).dx - send.left, 16);
    expect(send.right, 360 - 24, reason: '내용 폭 312 의 오른쪽 끝');
  });

  testWidgets('⑩ 보내는 중 — 번호 칸 잠김 · 받기에 스피너 + "보내는 중", 두 번 눌러도 한 번', (tester) async {
    repository.sendGate = Completer<void>();
    await pumpScreen(tester);
    await typePhone(tester);

    await tester.tap(sendButton);
    await tester.pump();
    await tester.tap(button('보내는 중'), warnIfMissed: false);
    await tester.pump();

    expect(repository.sentPhones, ['01001352468']);
    expectPhoneLocked(tester);
    final sending = button('보내는 중');
    final spinner = find.descendant(of: sending, matching: find.byType(CircularProgressIndicator));
    expect(tester.getSize(spinner), const Size(20, 20));
    expect(tester.widget<CircularProgressIndicator>(spinner).color, AppColors.disabled);
    expect(tester.getTopLeft(find.text('보내는 중')).dx - tester.getTopRight(spinner).dx, 8);

    repository.sendGate!.complete();
    await tester.pump();
    await close(tester);
  });

  testWidgets('③ 보낸 뒤 — 인증번호 줄(라벨 · 6자리 숫자 · 타이머 #C4224B · 확인 분홍 · 안내 · 다시 받기 회색)', (tester) async {
    await pumpScreen(tester);
    await sendCode(tester);
    await elapse(tester, const Duration(seconds: 15));

    expect(find.text('인증번호'), findsOneWidget);
    expect(codeField, findsOneWidget);
    expectPhoneNormal(tester);
    expect(isEnabled(tester, sendButton), isFalse, reason: '③ 받기는 회색(스피너 없음)');
    expect(find.descendant(of: sendButton, matching: find.byType(CircularProgressIndicator)), findsNothing);

    // 타이머(TrailingIcon 자리) 14/600 primary-text, 상자 오른쪽 안쪽 16.
    final timer = find.text('2:45');
    expect(timer, findsOneWidget);
    expect(textColor(tester, '2:45'), AppColors.primaryText);
    expect(tester.widget<Text>(timer).style?.fontSize, 14);
    expect(tester.widget<Text>(timer).style?.fontWeight, FontWeight.w600);
    final box = tester.getRect(codeField);
    expect(box.right - tester.getTopRight(timer).dx, 16);

    // 확인 62×52 자리: 상자 오른쪽 8. 6자리 전에는 회색(사용자 결정 11-10, pen ③ 도 같이 바꿈).
    final confirm = tester.getRect(button('확인'));
    expect(confirm.left - box.right, 8);
    expect(confirm.right, 360 - 24);
    expect(isEnabled(tester, button('확인')), isFalse);
    final confirmStyle =
        tester.widget<ElevatedButton>(find.descendant(of: button('확인'), matching: find.byType(ElevatedButton))).style!;
    expect(confirmStyle.backgroundColor?.resolve({WidgetState.disabled}), AppColors.primaryDisabled);
    expect(confirmStyle.foregroundColor?.resolve({WidgetState.disabled}), AppColors.disabled);
    await tester.enterText(codeField, '48291');
    await tester.pump();
    expect(isEnabled(tester, button('확인')), isFalse, reason: '5자리');
    await tester.enterText(codeField, '');
    await tester.pump();

    // 세로: 번호 칸 줄 → 8 → 입력 줄 → 8 → 안내 줄 → 8 → 다시 받기 48. 번호 도움말은 없다(사용자 결정 11-11).
    final hint = find.text('문자로 받은 6자리 숫자를 입력해 주세요');
    expect(hint, findsOneWidget);
    expect(find.descendant(of: find.ancestor(of: hint, matching: find.byType(Row)).first, matching: find.byType(Icon3d)),
        findsOneWidget);
    expect(tester.getTopLeft(find.text('인증번호')).dy - tester.getRect(phoneField).bottom, 8);
    expect(tester.getTopLeft(hint).dy - box.bottom, 8);
    final resend = find.text('0:45 뒤 다시 받기');
    expect(resend, findsOneWidget);
    expect(textColor(tester, '0:45 뒤 다시 받기'), AppColors.disabled);
    expect(tester.widget<Text>(resend).style?.fontSize, 14);
    final resendBox = tester.getRect(find.ancestor(of: resend, matching: find.byType(InkWell)).first);
    expect(resendBox.height, 48);
    expect(resendBox.left, 24, reason: '왼쪽 정렬 · 안쪽 0');
    expect(resendBox.top - tester.getBottomLeft(hint).dy, closeTo(8, 0.5));

    await tester.tap(resend);
    await tester.pump();
    expect(repository.sentPhones, hasLength(1), reason: '대기 중 다시 받기는 눌리지 않는다');
    await close(tester);
  });

  testWidgets('인증번호 칸 — 숫자 키보드 · 문자 자동 채움 · 6자리에서 끊기, 6자리를 치면 한 번만 자동 확인', (tester) async {
    repository.verifyGate = Completer<void>();
    await pumpScreen(tester);
    await sendCode(tester);

    final code = textField(tester, codeField);
    expect(code.keyboardType, TextInputType.number);
    expect(code.autofillHints, contains(AutofillHints.oneTimeCode));

    await tester.enterText(codeField, '4829157');
    await tester.pump();

    expect(textField(tester, codeField).controller!.text, '482915');
    expect(repository.verifiedCodes, [('01001352468', '482915')]);

    // ⑪ 확인 중 — 확인 버튼 스피너 + "확인 중", 오류 자리에 진행 줄, 번호 칸 잠김 모양.
    final verifying = button('확인 중');
    expect(find.descendant(of: verifying, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(isEnabled(tester, verifying), isFalse);
    expect(find.text('확인하고 있어요…'), findsOneWidget);
    expect(textColor(tester, '확인하고 있어요…'), AppColors.muted);
    expect(find.text('문자로 받은 6자리 숫자를 입력해 주세요'), findsNothing);
    expectPhoneLocked(tester);
    expect(find.text('인증번호 받기'), findsOneWidget, reason: '⑪ 받기는 회색 "인증번호 받기"');

    await tester.tap(verifying, warnIfMissed: false);
    await tester.pump();
    expect(repository.verifiedCodes, hasLength(1));

    repository.verifyGate!.complete();
    await tester.pump();
  });

  testWidgets('④ 틀렸을 때 — 인증번호 상자 테두리 error 2, 안내 대신 남은 기회 오류, 확인은 분홍', (tester) async {
    repository.nextVerifyResult = const FailureResult(
      ServerRejectedFailure('mismatch', code: 'phone_code_mismatch', remainingAttempts: 4),
    );
    await pumpScreen(tester);
    await sendCode(tester);

    await tester.enterText(codeField, '482915');
    await tester.pump();

    expect(enabledSide(tester, codeField), const BorderSide(color: AppColors.error, width: 2));
    expect(decoration(tester, codeField).fillColor, AppColors.surfaceSoft);
    expectStatusLine(tester, '인증번호가 맞지 않아요. (남은 기회 4번)', icon: AppIcons.circleAlert, color: AppColors.error);
    expect(find.text('문자로 받은 6자리 숫자를 입력해 주세요'), findsNothing);
    expect(isEnabled(tester, button('확인')), isTrue);
    await close(tester);
  });

  testWidgets('⑤ 시간이 지나면 — 타이머 0:00 회색, 확인 회색, 오류 줄, 다시 받기 분홍', (tester) async {
    await pumpScreen(tester);
    await sendCode(tester);

    await elapse(tester, const Duration(seconds: 180));

    expect(textColor(tester, '0:00'), AppColors.disabled);
    expect(isEnabled(tester, button('확인')), isFalse);
    expectStatusLine(tester, '시간이 지났어요. 인증번호를 다시 받아 주세요', icon: AppIcons.circleAlert, color: AppColors.error);
    expect(enabledSide(tester, codeField), const BorderSide(color: AppColors.hairline), reason: '⑤ 상자 보통');
    expect(textColor(tester, '다시 받기'), AppColors.primaryText);

    await tester.tap(find.text('다시 받기'));
    await tester.pump();
    expect(repository.sentPhones, hasLength(2));
    expect(find.text('3:00'), findsOneWidget);
    await close(tester);
  });

  testWidgets('⑥ 인증 성공 — 번호 칸 잠김 · 받기 대신 "번호 바꾸기" · 인증됐어요, 인증번호 줄 없음', (tester) async {
    await pumpScreen(tester);
    await sendCode(tester);

    await tester.enterText(codeField, '482915');
    await tester.pump();

    expectPhoneLocked(tester);
    expect(sendButton, findsNothing);
    expect(codeField, findsNothing);
    expectStatusLine(tester, '인증됐어요', icon: AppIcons.circleCheck, color: AppColors.success);
    final change = find.text('번호 바꾸기');
    expect(textColor(tester, '번호 바꾸기'), AppColors.primaryText);
    expect(tester.widget<Text>(change).style?.fontSize, 14);
    expect(tester.widget<Text>(change).style?.fontWeight, FontWeight.w600);
    final changeBox = tester.getRect(find.ancestor(of: change, matching: find.byType(InkWell)).first);
    expect(changeBox.height, 52);
    expect(tester.getTopLeft(change).dx - changeBox.left, 12);
    expect(changeBox.right - tester.getTopRight(change).dx, 12);
    expect(changeBox.left - tester.getRect(phoneField).right, 8);
    expect(changeBox.bottom, tester.getRect(phoneField).bottom);
    // 상태 줄은 입력 줄 바닥 8 아래(pen y=85).
    expect(tester.getTopLeft(find.text('인증됐어요')).dy - tester.getRect(phoneField).bottom, 8);

    await tester.tap(change);
    await tester.pump();

    expectPhoneNormal(tester);
    expect(isEnabled(tester, sendButton), isTrue);
    expect(find.text('인증됐어요'), findsNothing);
  });

  testWidgets('⑦ 이미 쓰는 번호 — 번호 칸 테두리 error 2, 상태 줄 오류, 받기 분홍 그대로', (tester) async {
    repository.nextSendResult = const FailureResult(ServerRejectedFailure('in use', code: 'phone_number_in_use'));
    await pumpScreen(tester);

    await sendCode(tester);

    expect(enabledSide(tester, phoneField), const BorderSide(color: AppColors.error, width: 2));
    expect(decoration(tester, phoneField).fillColor, AppColors.surfaceSoft);
    expectStatusLine(tester, '이미 다른 계정에서 쓰는 번호예요', icon: AppIcons.circleAlert, color: AppColors.error);
    expect(isEnabled(tester, sendButton), isTrue);
    expect(codeField, findsNothing);
  });

  testWidgets('⑫ 받기 한도 — 번호 칸 보통, 상태 줄 오류, 받기 회색, 인증번호 줄 없음', (tester) async {
    repository.nextSendResult = const FailureResult(RateLimitedFailure('limit', 36000));
    await pumpScreen(tester);

    await sendCode(tester);

    expectPhoneNormal(tester);
    expectStatusLine(tester, '오늘은 인증번호를 더 받을 수 없어요', icon: AppIcons.circleAlert, color: AppColors.error);
    expect(isEnabled(tester, sendButton), isFalse);
    expect(codeField, findsNothing);
    await close(tester);
  });

  for (final (failure, text) in [
    (const ServerUnavailableFailure() as Failure, '잠시 후 다시 시도해 주세요'),
    (const ServerRejectedFailure('invalid', code: 'phone_number_invalid'), '010으로 시작하는 휴대폰 번호만 쓸 수 있어요'),
  ]) {
    testWidgets('"$text" 는 ⑫ 와 같은 자리 · 모양이다', (tester) async {
      repository.nextSendResult = FailureResult(failure);
      await pumpScreen(tester);

      await sendCode(tester);

      expectPhoneNormal(tester);
      expectStatusLine(tester, text, icon: AppIcons.circleAlert, color: AppColors.error);
    });
  }

  testWidgets('⑬ 5번 틀려 잠김 — 인증번호 상자 #F2F2F2 + error 2 · 값 · 타이머 회색, 확인 회색, 번호 칸 잠김', (tester) async {
    repository.nextVerifyResult = const FailureResult(ServerRejectedFailure('locked', code: 'phone_code_locked'));
    await pumpScreen(tester);
    await sendCode(tester);
    await elapse(tester, const Duration(seconds: 72));

    await tester.enterText(codeField, '123456');
    await tester.pump();

    expect(decoration(tester, codeField).fillColor, AppColors.surfaceStrong);
    expect(enabledSide(tester, codeField), const BorderSide(color: AppColors.error, width: 2));
    expect(textField(tester, codeField).style?.color, AppColors.disabled);
    expect(textField(tester, codeField).readOnly, isTrue);
    expect(textColor(tester, '1:48'), AppColors.disabled);
    expect(isEnabled(tester, button('확인')), isFalse);
    expectStatusLine(tester, '5번 틀려서 인증번호를 새로 받아야 해요', icon: AppIcons.circleAlert, color: AppColors.error);
    expect(textColor(tester, '다시 받기'), AppColors.primaryText);
    expectPhoneLocked(tester);
    await close(tester);
  });

  // 번호 도움말을 뺀 뒤(사용자 결정 11-11) 번호 덩어리와 「성별 · 필수」 사이는, 도움말 없는 키 칸 상자 바닥 → 「전화번호 · 필수」 와 같은 24
  // (출생연도 도움말 줄 16.8 + 줄 사이 8 = 24.8 을 토큰 AppSpacing.lg 로).
  group('번호 덩어리 → 「성별 · 필수」 24', () {
    double gapAbove(WidgetTester tester, double bottom) => tester.getTopLeft(find.text('성별 · 필수')).dy - bottom;

    testWidgets('번호 줄만 있을 때(①) — 번호 상자 바닥에서 24, 도움말 없음', (tester) async {
      await pumpScreen(tester);

      expect(find.text('다른 사람이 나를 지인으로 등록했을 때만 사용돼요'), findsNothing);
      expect(gapAbove(tester, tester.getRect(phoneField).bottom), 24);
    });

    testWidgets('상태 줄이 있을 때(⑦) — 상태 줄 바닥에서 24', (tester) async {
      repository.nextSendResult = const FailureResult(ServerRejectedFailure('in use', code: 'phone_number_in_use'));
      await pumpScreen(tester);
      await sendCode(tester);

      expect(gapAbove(tester, tester.getBottomLeft(find.text('이미 다른 계정에서 쓰는 번호예요')).dy), 24);
    });

    testWidgets('인증번호 줄이 있을 때(③) — 다시 받기 48 바닥에서 24', (tester) async {
      await pumpScreen(tester);
      await sendCode(tester);

      final resend = find.ancestor(of: find.text('1:00 뒤 다시 받기'), matching: find.byType(InkWell)).first;
      expect(gapAbove(tester, tester.getRect(resend).bottom), 24);
      await close(tester);
    });
  });

  // 뷰모델은 앱이 켜진 동안 살아 있다(autoDispose 아님). 화면이 사라지면 1초 시계를 멈추고, 돌아오면 마감 시각으로 다시 센다.
  testWidgets('화면이 사라지면 뷰모델이 살아 있어도 1초 시계가 멈추고, 돌아오면 남은 시간을 다시 센다', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 바뀜은 관찰자로 센다 — 시험이 직접 듣고 있으면(listen) 듣는 쪽이 남아 화면이 사라진 것이 되지 않는다.
    final updates = _UpdateCounter();
    final container = ProviderContainer(
      observers: [updates],
      overrides: [
        basicInfoNowProvider.overrideWithValue(() => now),
        basicInfoRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);
    Widget app(Widget home) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        );
    await tester.pumpWidget(app(const BasicInfoScreen()));
    await sendCode(tester);
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pump();
    final afterLeave = updates.count;

    await elapse(tester, const Duration(seconds: 20));

    expect(updates.count, afterLeave, reason: '화면이 없는 동안 매초 다시 그리지 않는다');

    await tester.pumpWidget(app(const BasicInfoScreen()));
    await tester.pump();

    expect(find.text('2:40'), findsOneWidget, reason: '마감 시각 기준이라 자리를 비운 20초도 빠진다');
    expect(find.text('0:40 뒤 다시 받기'), findsOneWidget);
    await elapse(tester, const Duration(seconds: 1));
    expect(find.text('2:39'), findsOneWidget, reason: '돌아오면 다시 1초마다 센다');
    // 다시 떠나고 container 는 닫지 않은 채 끝낸다 — 시계가 돌고 있으면 testWidgets 가 끝에서 "Timer is still pending" 으로 실패한다.
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pump();
  });

  testWidgets('"다음" 은 번호를 인증해야 켜진다', (tester) async {
    await pumpScreen(tester);
    // 닉네임 칸만 안내 글자(placeholder)가 없다.
    final nickname = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == null);
    await tester.enterText(nickname, '홍길동');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(field('예: 2003'), '2003');
    await tester.enterText(field('예: 170'), '170');
    await tester.tap(find.text('남성'));
    await sendCode(tester);

    expect(isEnabled(tester, button('다음')), isFalse);

    await tester.enterText(codeField, '482915');
    await tester.pump();

    expect(isEnabled(tester, button('다음')), isTrue);
  });
}

/// 뷰모델 상태가 바뀐 횟수(듣지 않고 센다).
final class _UpdateCounter extends ProviderObserver {
  int count = 0;

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) => count++;
}
