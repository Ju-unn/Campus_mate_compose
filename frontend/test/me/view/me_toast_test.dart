import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [MeToastHost] 를 쓰는 가장 작은 화면 — 버튼 둘이 서로 다른 토스트를 띄운다.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with MeToastHost<_Host> {
  @override
  Widget build(BuildContext context) {
    return MeToastLayer(
      toast: timedToast,
      child: Column(
        children: [
          TextButton(onPressed: () => showTimedToast(comingSoonToast(AppLocalizationsKo())), child: const Text('곧')),
          TextButton(onPressed: () => showTimedToast(const AppToast(label: '다른 안내')), child: const Text('다른')),
        ],
      ),
    );
  }
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: _Host())));
  }

  testWidgets('"곧 열려요" 는 clock3 16 흰색 + 글자(N4 · C5 — 15 와 15-5 가 같이 쓴다)', (tester) async {
    final toast = comingSoonToast(AppLocalizationsKo());
    expect(toast.label, '곧 열려요');
    final icon = toast.leading! as Icon;
    expect((icon.icon, icon.size, icon.color), (AppIcons.clock3, 16, AppColors.onInk));
  });

  testWidgets('띄우면 [MeToastHost.duration](2초) 동안 화면 아래 12 · 가로 가운데에 보이고, 흐려지며 사라진다', (tester) async {
    await pump(tester);
    expect(find.byType(AppToast), findsNothing);

    await tester.tap(find.text('곧'));
    await tester.pump();

    final toast = find.byType(AppToast);
    expect(toast, findsOneWidget);
    expect(tester.getBottomLeft(toast).dy, 640 - 12);
    expect(tester.getCenter(toast).dx, 180);
    await tester.pump(MeToastHost.duration - const Duration(milliseconds: 1));
    expect(toast, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1)); // 2초 — 흐려지기 시작
    await tester.pump(AppMotion.disappear + const Duration(milliseconds: 1));
    expect(toast, findsNothing);
  });

  group('나타나고 사라지는 움직임 — 제자리 fade(사용자 2026-11-16 「토스트는 제자리에서 fade로 나타났다 사라지게」)', () {
    Finder toast() => find.byType(AppToast);
    double opacity(WidgetTester tester) {
      var value = 1.0;
      for (final fade in tester.widgetList<FadeTransition>(find.ancestor(of: toast(), matching: find.byType(FadeTransition)))) {
        value *= fade.opacity.value;
      }
      return value;
    }

    testWidgets('투명에서 appear(220ms) 동안 제자리에서 나타난다(올라오지 않는다)', (tester) async {
      await pump(tester);
      await tester.tap(find.text('곧'));
      await tester.pump();

      expect(tester.getBottomLeft(toast()).dy, 640 - 12);
      expect(opacity(tester), 0);

      await tester.pump(AppMotion.appear);
      expect(tester.getBottomLeft(toast()).dy, 640 - 12);
      expect(opacity(tester), 1);
    });

    testWidgets('떠 있는 안내가 다른 안내로 바뀔 때는 다시 나타나지 않는다(제자리에서 글만 바뀐다)', (tester) async {
      await pump(tester);
      await tester.tap(find.text('곧'));
      await tester.pump(); // 첫 안내를 그려 올라오기 시작
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('다른'));
      await tester.pump();

      expect(find.text('다른 안내'), findsOneWidget);
      expect(tester.getBottomLeft(toast()).dy, 640 - 12);
      expect(opacity(tester), 1);
    });

    testWidgets('기기 "동작 줄이기" 면 처음부터 다 보인다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);
      await tester.tap(find.text('곧'));
      await tester.pump();

      expect(tester.getBottomLeft(toast()).dy, 640 - 12);
      expect(opacity(tester), 1);
    });
  });

  testWidgets('한 번에 하나 — 새 안내가 떠 있던 것을 바로 바꾸고, 시간은 새로 잰다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('곧'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('다른'));
    await tester.pump();

    expect(find.byType(AppToast), findsOneWidget);
    expect(find.text('곧 열려요'), findsNothing);
    expect(find.text('다른 안내'), findsOneWidget);
    // 첫 안내가 사라질 때(2초)에도 새 안내는 남는다.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('다른 안내'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(AppMotion.disappear + const Duration(milliseconds: 1)); // 흐려지며 사라지는 시간
    expect(find.text('다른 안내'), findsNothing);
  });

  testWidgets('떠 있는 동안 화면이 닫혀도 타이머가 남지 않는다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('곧'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    // 남은 타이머가 있으면 테스트 끝 검사가 "A Timer is still pending" 으로 떨어진다.
    expect(find.byType(AppToast), findsNothing);
  });
}
