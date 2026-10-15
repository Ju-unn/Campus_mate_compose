import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/back_exit/back_exit_view_model.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _hint = '한 번 더 누르면 종료돼요';

/// 시험이 시계를 쥐고 흔든다 — 2초 판정은 이 시계로만 한다.
late DateTime _now;

/// `SystemNavigator.pop` 이 불린 횟수(= 앱이 닫히려는 횟수).
late int _exitCalls;

Future<void> _pump(
  WidgetTester tester, {
  Widget? home,
  bool disableAnimations = false,
  VoidCallback? onHint,
}) async {
  _now = DateTime(2026, 10, 13, 12);
  _exitCalls = 0;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') _exitCalls++;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [backExitClockProvider.overrideWithValue(() => _now)],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: home ??
            BackExitScope(
              onHint: onHint,
              child: const Scaffold(body: Center(child: Text('최상위'))),
            ),
      ),
    ),
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

/// 토스트가 뜬 뒤 2초를 기다려 걷힐 때까지 돌린다(SnackBar 의 시간은 올라온 뒤부터 센다).
Future<void> _waitUntilHintGone(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(backExitWindow);
  await tester.pumpAndSettle();
}

/// 토스트 글자 위에 걸린 FadeTransition 들의 투명도를 곱한 값 — 1 이면 완전히 보인다.
double _hintOpacity(WidgetTester tester) {
  final fades = find.ancestor(of: find.text(_hint), matching: find.byType(FadeTransition)).evaluate();
  return fades.fold(1.0, (value, element) => value * (element.widget as FadeTransition).opacity.value);
}

void main() {
  group('안드로이드', () {
    final android = TargetPlatformVariant.only(TargetPlatform.android);

    testWidgets('첫 뒤로가기는 앱을 닫지 않고 "한 번 더 누르면 종료돼요" 를 보여 준다', (tester) async {
      await _pump(tester);

      await _back(tester);

      expect(find.text(_hint), findsOneWidget);
      expect(_exitCalls, 0);
      expect(find.text('최상위'), findsOneWidget);
    }, variant: android);

    testWidgets('2초 안에 한 번 더 누르면 앱을 닫는다', (tester) async {
      await _pump(tester);
      await _back(tester);

      _now = _now.add(const Duration(milliseconds: 1500));
      await _back(tester);

      expect(_exitCalls, 1);
    }, variant: android);

    testWidgets('2초가 지난 뒤에 누르면 닫지 않고 다시 안내한다', (tester) async {
      await _pump(tester);
      await _back(tester);
      await _waitUntilHintGone(tester);
      expect(find.text(_hint), findsNothing);

      _now = _now.add(const Duration(seconds: 3));
      await _back(tester);

      expect(_exitCalls, 0);
      expect(find.text(_hint), findsOneWidget);
    }, variant: android);

    testWidgets('안내 토스트는 읽어 주는 영역(live region)이다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _back(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.getSemantics(find.bySemanticsLabel(_hint)), isSemantics(label: _hint, isLiveRegion: true));
      handle.dispose();
    }, variant: android);

    testWidgets('안내 토스트는 2초 뒤에 사라진다', (tester) async {
      await _pump(tester);
      await _back(tester);
      expect(find.text(_hint), findsOneWidget);

      await _waitUntilHintGone(tester);

      expect(find.text(_hint), findsNothing);
    }, variant: android);

    testWidgets('모션 줄이기를 켜면 토스트가 애니메이션 없이 바로 제자리에 뜬다', (tester) async {
      await _pump(tester, disableAnimations: true);

      await _back(tester);

      expect(_hintOpacity(tester), 1);
    }, variant: android);

    testWidgets('모션 줄이기가 꺼져 있으면 토스트는 서서히 나타난다 (위 시험의 대조)', (tester) async {
      await _pump(tester);

      await _back(tester);

      expect(_hintOpacity(tester), lessThan(1));
    }, variant: android);

    testWidgets('onHint 를 주면 기본 토스트 대신 그 함수를 부른다', (tester) async {
      var hints = 0;
      await _pump(tester, onHint: () => hints++);

      await _back(tester);

      expect(hints, 1);
      expect(find.text(_hint), findsNothing);
      expect(_exitCalls, 0);
    }, variant: android);

    // 설문 이전 문항 · 20d · 06-4 의 앱바 화살표처럼 화면 안에 돌아갈 곳이 있을 때.
    testWidgets('onBack 을 주면 안내 · 종료 대신 그것을 부른다', (tester) async {
      var backs = 0;
      await _pump(
        tester,
        home: BackExitScope(onBack: () => backs++, child: const Scaffold(body: Text('최상위'))),
      );

      await _back(tester);
      await _back(tester);

      expect(backs, 2);
      expect(find.text(_hint), findsNothing);
      expect(_exitCalls, 0);
    }, variant: android);

    testWidgets('위에 다른 화면이 열려 있으면 가로채지 않고 한 단계만 뒤로 간다', (tester) async {
      await _pump(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('상세'))));
      await tester.pumpAndSettle();

      await _back(tester);
      await tester.pumpAndSettle();

      expect(find.text('최상위'), findsOneWidget);
      expect(find.text('상세'), findsNothing);
      expect(find.text(_hint), findsNothing);
      expect(_exitCalls, 0);
    }, variant: android);

    testWidgets('시트가 열려 있으면 시트만 닫는다', (tester) async {
      await _pump(tester);
      final context = tester.element(find.text('최상위'));
      showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 100, child: Text('시트')));
      await tester.pumpAndSettle();

      await _back(tester);
      await tester.pumpAndSettle();

      expect(find.text('시트'), findsNothing);
      expect(find.text(_hint), findsNothing);
      expect(_exitCalls, 0);
    }, variant: android);

    testWidgets('다른 화면 위에 올라온 탭이면 안내 없이 그 화면으로 돌아간다 (알림 → 오늘 탭 push)', (tester) async {
      await _pump(
        tester,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BackExitScope(child: Scaffold(body: Text('탭')))),
              ),
              child: const Text('알림'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('알림'));
      await tester.pumpAndSettle();

      await _back(tester);
      await tester.pumpAndSettle();

      expect(find.text('알림'), findsOneWidget);
      expect(find.text(_hint), findsNothing);
      expect(_exitCalls, 0);
    }, variant: android);
  });

  group('안드로이드가 아닐 때', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      testWidgets('$platform: 가로채지 않는다 — 안내가 뜨지 않고 기본 동작이 그대로 나온다', (tester) async {
        await _pump(tester);

        await _back(tester);

        expect(find.text(_hint), findsNothing);
        // 가로채지 않으니 기본 동작이 그대로 나온다 — 맨 아래 화면에서 받아 줄 곳이 없어 앱 종료 요청이 간다.
        expect(_exitCalls, 1);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('$platform: onBack 을 줘도 가로채지 않는다', (tester) async {
        var backs = 0;
        await _pump(tester, home: BackExitScope(onBack: () => backs++, child: const Scaffold(body: Text('최상위'))));

        await _back(tester);

        expect(backs, 0);
        expect(_exitCalls, 1);
      }, variant: TargetPlatformVariant.only(platform));
    }
  });
}
