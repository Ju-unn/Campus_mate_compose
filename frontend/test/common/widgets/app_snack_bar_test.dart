import 'package:campus_mate/common/widgets/app_snack_bar.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 찾은 위젯 위에 겹친 투명도를 모두 곱한 값 — 화면에 실제로 보이는 정도.
double _opacity(WidgetTester tester, Finder finder) {
  var value = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)))) {
    value *= fade.opacity.value;
  }
  return value;
}

const _label = '복사했어요';

/// 안쪽(실제로 그려지는) SnackBar. 바깥 움직임 SnackBar 는 다른 타입이라 잡히지 않는다.
final _bar = find.byType(SnackBar);

SnackBar _toastBar({Duration duration = const Duration(seconds: 3)}) => SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      duration: duration,
      content: const Center(child: AppToast(label: _label)),
    );

void main() {
  late ScaffoldMessengerState messenger;

  Future<void> pumpHost(WidgetTester tester, {bool reduceMotion = false}) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    ));
    messenger = tester.state(find.byType(ScaffoldMessenger));
  }

  /// 떠 있는 SnackBar 의 표시 타이머가 시험 끝에 남지 않게 지운다.
  Future<void> clear(WidgetTester tester) async {
    messenger.removeCurrentSnackBar();
    await tester.pump();
  }

  group('스낵바(띠) — 아래에서 올라오고 같은 길로 내려간다(사용자 2026-11-16)', () {
    testWidgets('들어올 때 easeOut 으로 220ms 동안 자기 높이만큼 아래에서 올라온다(투명도 · 크기는 그대로)', (tester) async {
      await pumpHost(tester);
      showAppSnackBar(messenger, const SnackBar(content: Text(_label)));
      await tester.pump(); // 첫 장면(t = 0)
      final start = tester.getRect(_bar);
      await tester.pump(AppMotion.appear ~/ 2);
      final mid = tester.getRect(_bar);
      expect(_opacity(tester, find.text(_label)), 1);
      await tester.pump(AppMotion.appear ~/ 2);
      final rest = tester.getRect(_bar);

      // SnackBar 기본 움직임(높이로 드러내기 · 가운데 구간 fade)이 없다 — 처음부터 다 그려진 채 움직인다.
      expect(start.size, rest.size);
      expect(start.left, rest.left);
      expect(start.top - rest.top, closeTo(rest.height, 0.01));
      expect(mid.top - rest.top, closeTo(rest.height * (1 - Curves.easeOut.transform(0.5)), 0.01));
      await clear(tester);
    });

    testWidgets('나갈 때 easeIn 으로 180ms 동안 같은 길로 내려가고 사라진다', (tester) async {
      await pumpHost(tester);
      showAppSnackBar(messenger, const SnackBar(content: Text(_label)));
      await tester.pump();
      await tester.pump(AppMotion.appear);
      final rest = tester.getRect(_bar);

      messenger.hideCurrentSnackBar();
      await tester.pump(); // 사라지기 시작(τ = 0)
      await tester.pump(AppMotion.disappear ~/ 2);
      final mid = tester.getRect(_bar);
      expect(mid.left, rest.left);
      expect(mid.top - rest.top, closeTo(rest.height * Curves.easeIn.transform(0.5), 0.01));

      await tester.pump(AppMotion.disappear ~/ 2 - const Duration(milliseconds: 1));
      expect(find.text(_label), findsOneWidget);
      // Flutter 애니메이션은 시간을 "넘긴" 첫 장면에서 끝난다(같은 시각의 장면은 아직 진행 중).
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.text(_label), findsNothing);
    });

    testWidgets('SnackBar 에 준 표시 시간을 그대로 쓴다', (tester) async {
      await pumpHost(tester);
      showAppSnackBar(messenger, const SnackBar(content: Text(_label), duration: Duration(seconds: 1)));
      await tester.pumpAndSettle(); // 다 올라온 장면부터 1초를 잰다(메신저 규칙)
      await tester.pump(const Duration(milliseconds: 999));
      expect(find.text(_label), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1)); // 1초 — 내려가기 시작
      await tester.pump();
      await tester.pump(AppMotion.disappear + const Duration(milliseconds: 1));
      expect(find.text(_label), findsNothing);
    });
  });

  group('토스트 알약을 SnackBar 자리에 띄울 때 — 제자리 fade(사용자 「토스트는 제자리에서 fade」)', () {
    testWidgets('자리는 그대로이고 easeOut 으로 220ms 동안 나타난다', (tester) async {
      await pumpHost(tester);
      showToastSnackBar(messenger, _toastBar());
      await tester.pump();
      final toast = find.byType(AppToast);
      final start = tester.getRect(toast);
      expect(_opacity(tester, toast), 0);

      await tester.pump(AppMotion.appear ~/ 2);
      expect(tester.getRect(toast), start);
      expect(_opacity(tester, toast), closeTo(Curves.easeOut.transform(0.5), 1e-6));

      await tester.pump(AppMotion.appear ~/ 2);
      expect(tester.getRect(toast), start);
      expect(_opacity(tester, toast), 1);
      await clear(tester);
    });

    testWidgets('easeIn 으로 180ms 동안 제자리에서 흐려지며 사라진다', (tester) async {
      await pumpHost(tester);
      showToastSnackBar(messenger, _toastBar());
      await tester.pump();
      await tester.pump(AppMotion.appear);
      final toast = find.byType(AppToast);
      final rest = tester.getRect(toast);

      messenger.hideCurrentSnackBar();
      await tester.pump();
      await tester.pump(AppMotion.disappear ~/ 2);
      expect(tester.getRect(toast), rest);
      expect(_opacity(tester, toast), closeTo(1 - Curves.easeIn.transform(0.5), 1e-6));

      await tester.pump(AppMotion.disappear ~/ 2 + const Duration(milliseconds: 1));
      expect(toast, findsNothing);
    });
  });

  testWidgets('스낵바 → 토스트를 바로 이어 띄워도 줄이 멈추지 않는다(시간이 늘 같아 컨트롤러를 버리지 않는다)', (tester) async {
    await pumpHost(tester);
    showAppSnackBar(messenger, const SnackBar(content: Text('먼저')));
    await tester.pump(const Duration(milliseconds: 50));
    messenger.hideCurrentSnackBar();
    showToastSnackBar(messenger, _toastBar());
    await tester.pumpAndSettle();

    expect(find.text('먼저'), findsNothing);
    expect(find.text(_label), findsOneWidget);
    expect(_opacity(tester, find.byType(AppToast)), 1);
    await clear(tester);
  });

  testWidgets('기기 "동작 줄이기" 면 스낵바 · 토스트 모두 첫 장면부터 제자리 · 다 보인다', (tester) async {
    await pumpHost(tester, reduceMotion: true);
    showAppSnackBar(messenger, const SnackBar(content: Text('띠')));
    await tester.pump();
    final first = tester.getRect(_bar);
    expect(_opacity(tester, find.text('띠')), 1);
    await tester.pump(AppMotion.appear);
    expect(tester.getRect(_bar), first);
    messenger.removeCurrentSnackBar();
    await tester.pump();

    showToastSnackBar(messenger, _toastBar());
    await tester.pump();
    expect(_opacity(tester, find.byType(AppToast)), 1);
    await clear(tester);
  });
}
