import 'dart:async';

import 'package:campus_mate/auth/view/sign_up_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';
import '../../graduate/view/gate_screen_harness.dart';

/// pen 02 학교 메일 입력 — 인증 방법 선택 뒤 `dM4P7`(값표 §2). 원본 `emHNY` 와 다른 점은 앱바 뒤로 화살표 하나다.
/// 방법 고르기를 거치지 않은 옛 길(`needsSchoolEmail`)은 지금과 같다 — 화살표 없음, 시스템 뒤로 = 종료 안내.
void main() {
  late GateHarness harness;
  late int exitCalls;

  setUpAll(loadPretendard);
  setUp(() {
    harness = GateHarness();
    exitCalls = 0;
  });

  Future<void> pump(WidgetTester tester, {required bool hasMethodPicker, double textScale = 1}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exitCalls++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await harness.pump(tester, SignUpScreen(hasMethodPicker: hasMethodPicker), textScale: textScale);
  }

  group('방법 고르기를 거쳐 온 02 (needsSchoolEmailChosen)', () {
    testWidgets('앱바 높이 56 · 왼쪽 12 · 뒤로 48×48(arrow-left 22)이 있다', (tester) async {
      await pump(tester, hasMethodPicker: true);

      expect(tester.getSize(find.byType(AppBar)).height, 56);
      final arrow = find.byTooltip(onboardingBackLabel);
      expect(tester.getSize(arrow), const Size(48, 48));
      expect(tester.getTopLeft(arrow).dx, 12);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft)).size, 22);
    });

    testWidgets('본문은 원본보다 앱바 56 만큼 내려간다 (일러스트 위가 56)', (tester) async {
      await pump(tester, hasMethodPicker: true);

      expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Image).first).dy, 56);
    });

    testWidgets('화살표: 서버 값을 비우는 호출 한 번(null), 종료 안내는 없다', (tester) async {
      await pump(tester, hasMethodPicker: true);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();

      expect(harness.repository.chosen, [null]);
      expect(find.text(backExitMessage), findsNothing);
    });

    testWidgets('시스템 뒤로: 화살표와 같은 호출 한 번, 종료 안내 토스트 · 종료 없음', (tester) async {
      await pump(tester, hasMethodPicker: true);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(harness.repository.chosen, [null]);
      expect(find.text(backExitMessage), findsNothing);
      expect(exitCalls, 0);
    });

    testWidgets('비우는 중에 화살표와 시스템 뒤로를 또 눌러도 비우기는 한 번이다', (tester) async {
      harness.repository.holdChoose = Completer<void>();
      await pump(tester, hasMethodPicker: true);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.binding.handlePopRoute();
      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();

      expect(harness.repository.chosen, hasLength(1));
      harness.repository.holdChoose!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('비우기에 실패하면 02 에 머물고 안내 토스트가 뜬다', (tester) async {
      harness.repository.chooseResult = const FailureResult(NetworkFailure());
      await pump(tester, hasMethodPicker: true);

      await tester.tap(find.byTooltip(onboardingBackLabel));
      await tester.pump();
      await tester.pump();

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      expect(find.text('대학 이메일로 시작해요'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('BackExitScope 는 한 겹이다(화면이 스스로 두른다)', (tester) async {
      await pump(tester, hasMethodPicker: true);

      expect(find.byType(BackExitScope), findsOneWidget);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 $scale배에서 넘침 예외가 없다', (tester) async {
        await pump(tester, hasMethodPicker: true, textScale: scale);

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('옛 길 02 (needsSchoolEmail, 서버 플래그 꺼짐) — 지금과 같다 [RF5]', () {
    testWidgets('앱바 · 화살표가 없고 일러스트가 맨 위(0)에서 시작한다', (tester) async {
      await pump(tester, hasMethodPicker: false);

      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip(onboardingBackLabel), findsNothing);
      expect(tester.getTopLeft(find.byType(Image).first).dy, 0);
    });

    testWidgets('시스템 뒤로는 종료 안내, 한 번 더 누르면 앱을 닫고 서버는 부르지 않는다', (tester) async {
      await pump(tester, hasMethodPicker: false);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text(backExitMessage), findsOneWidget);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);
      expect(harness.repository.chosen, isEmpty);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('BackExitScope 는 한 겹이다', (tester) async {
      await pump(tester, hasMethodPicker: false);

      expect(find.byType(BackExitScope), findsOneWidget);
    });
  });
}
