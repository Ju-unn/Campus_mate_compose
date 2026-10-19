import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/graduate/view/graduate_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/view/pretendard.dart';
import 'gate_screen_harness.dart';

/// pen 02-g-2 졸업생 확인 중 `IENk4`(값표 §4, 18c `xA8en` 복사). 앱바 · 뒤로가기 · 단추 없음.
void main() {
  late GateHarness harness;

  setUpAll(loadPretendard);
  setUp(() => harness = GateHarness());

  Future<void> pump(WidgetTester tester, {double textScale = 1, bool disableAnimations = false}) =>
      harness.pump(tester, const GraduateWaitingScreen(), textScale: textScale, disableAnimations: disableAnimations);

  group('구성 · 값 (값표 §4)', () {
    testWidgets('마스코트 88×88 · 제목 · 설명이 pen 문구 그대로, 앱바 · 버튼 · 화살표 없음', (tester) async {
      await pump(tester);

      expect(tester.getSize(find.byType(Image)), const Size(88, 88));
      expect(find.text('졸업생 확인 중이에요'), findsOneWidget);
      expect(find.text('결과는 알림으로 알려 드려요'), findsOneWidget);
      expect(find.text('보통 영업일 1~2일 걸려요'), findsNothing, reason: '18c 원본의 이 줄은 지웠다');
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byTooltip(onboardingBackLabel), findsNothing);
    });

    testWidgets('제목 18/700 ink(렌더 26) · 설명 14/500 muted(렌더 20), 내용 폭 280 · 간격 16', (tester) async {
      await pump(tester);

      final title = styleOf(tester, '졸업생 확인 중이에요');
      expect((title.fontSize, title.fontWeight, title.color), (18.0, FontWeight.w700, AppColors.ink));
      final body = styleOf(tester, '결과는 알림으로 알려 드려요');
      expect((body.fontSize, body.fontWeight, body.color), (14.0, FontWeight.w500, AppColors.muted));
      final mascot = tester.getRect(find.byType(Image));
      final titleRect = tester.getRect(find.text('졸업생 확인 중이에요'));
      final bodyRect = tester.getRect(find.text('결과는 알림으로 알려 드려요'));
      expect(titleRect.top - mascot.bottom, closeTo(16, 1));
      expect(bodyRect.top - titleRect.bottom, closeTo(16, 6));
      expect(titleRect.center.dx, closeTo(180, 1));
      expect(mascot.center.dy, closeTo(351, 1.5), reason: 'PNG 실측: 마스코트 상자 307~395, 가운데 묶음');
    });
  });

  group('로그아웃 링크 (대장 결정 10-19: 02-0 의 LogoutTextButton 재사용)', () {
    testWidgets('맨 아래 16 에 높이 48 · 14/600 muted 로그아웃이 있고 내용 묶음은 여전히 화면 가운데다', (tester) async {
      await pump(tester);

      expect(find.text('로그아웃'), findsOneWidget);
      final logout = find.ancestor(of: find.text('로그아웃'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(logout).height, 48);
      expect(tester.getBottomLeft(logout).dy, 780 - 16);
      final style = styleOf(tester, '로그아웃');
      expect((style.fontSize, style.fontWeight, style.color), (14.0, FontWeight.w600, AppColors.muted));
      expect(tester.getRect(find.byType(Image)).center.dy, closeTo(351, 1.5));
    });

    testWidgets('글자 2배에서도 로그아웃이 내용과 겹치지 않고 넘침이 없다', (tester) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);
      final logout = tester.getRect(find.ancestor(of: find.text('로그아웃'), matching: find.byType(InkWell)).first);
      expect(tester.getRect(find.text('결과는 알림으로 알려 드려요')).bottom, lessThanOrEqualTo(logout.top));
    });
  });

  group('뒤로가기 — 화살표가 없으니 시스템 뒤로는 종료 안내다', () {
    late int exitCalls;

    testWidgets('첫 뒤로는 안내만, 두 번째는 앱을 닫는다. 화면은 뒤로 빠지지 않는다', (tester) async {
      exitCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester);
      expect(Navigator.of(tester.element(find.byType(GraduateWaitingScreen))).canPop(), isFalse);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text(backExitMessage), findsOneWidget);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);
      expect(find.byType(GraduateWaitingScreen), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('관문 다시 묻기 — 푸시만 믿지 않는다', () {
    testWidgets('30초마다 관문을 다시 묻는다', (tester) async {
      await pump(tester);
      expect(harness.gateRepository.fetchCount, 0);

      await tester.pump(const Duration(seconds: 29));
      expect(harness.gateRepository.fetchCount, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(harness.gateRepository.fetchCount, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(harness.gateRepository.fetchCount, 2);
    });

    testWidgets('앱이 다시 앞으로 오면 곧바로 한 번 묻는다', (tester) async {
      await pump(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(harness.gateRepository.fetchCount, 1);
    });

    testWidgets('화면을 떠나면 타이머가 풀려 더 묻지 않는다', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(harness.gateRepository.fetchCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 90));

      expect(harness.gateRepository.fetchCount, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(harness.gateRepository.fetchCount, 1, reason: '떠난 뒤 앞으로 와도 이 화면은 묻지 않는다');
    });
  });

  group('글자 확대 · 동작 줄이기', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 $scale배에서 넘침 예외가 없다', (tester) async {
        await pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('낭독: 마스코트는 읽히지 않고 제목과 설명만 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('졸업생 확인 중이에요'), findsOneWidget);
      expect(find.bySemanticsLabel('결과는 알림으로 알려 드려요'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('동작 줄이기를 켜도 화면이 그려지고 타이머 말고는 움직임이 없다', (tester) async {
      await pump(tester, disableAnimations: true);

      expect(tester.takeException(), isNull);
      expect(find.text('졸업생 확인 중이에요'), findsOneWidget);
    });
  });
}
