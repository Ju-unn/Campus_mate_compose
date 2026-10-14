import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
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
          TextButton(onPressed: () => showTimedToast(comingSoonToast), child: const Text('곧')),
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
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
  }

  testWidgets('"곧 열려요" 는 clock3 16 흰색 + 글자(N4 · C5 — 15 와 15-5 가 같이 쓴다)', (tester) async {
    expect(comingSoonToast.label, '곧 열려요');
    final icon = comingSoonToast.leading! as Icon;
    expect((icon.icon, icon.size, icon.color), (AppIcons.clock3, 16, AppColors.onInk));
  });

  testWidgets('띄우면 [MeToastHost.duration](2초) 동안 화면 아래 12 · 가로 가운데에 보이고 사라진다', (tester) async {
    await pump(tester);
    expect(find.byType(AppToast), findsNothing);

    await tester.tap(find.text('곧'));
    await tester.pump();

    final toast = find.byType(AppToast);
    expect(toast, findsOneWidget);
    await tester.pump(AppMotion.press); // 올라오는 움직임(아래 D4)이 끝난 자리
    expect(tester.getBottomLeft(toast).dy, 640 - 12);
    expect(tester.getCenter(toast).dx, 180);
    await tester.pump(MeToastHost.duration - AppMotion.press - const Duration(milliseconds: 1));
    expect(toast, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(toast, findsNothing);
  });

  group('나타나는 움직임(D4 — 대화 탭 토스트처럼 투명 + 아래에서 올라온다)', () {
    Finder toast() => find.byType(AppToast);
    double opacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.ancestor(of: toast(), matching: find.byType(Opacity)).first).opacity;

    testWidgets('투명 · 아래 8 에서 press(120ms) 동안 제자리로 온다', (tester) async {
      await pump(tester);
      await tester.tap(find.text('곧'));
      await tester.pump();

      expect(tester.getBottomLeft(toast()).dy, 640 - 12 + 8);
      expect(opacity(tester), 0);

      await tester.pump(AppMotion.press);
      expect(tester.getBottomLeft(toast()).dy, 640 - 12);
      expect(opacity(tester), 1);
    });

    testWidgets('떠 있는 안내가 다른 안내로 바뀔 때는 다시 올라오지 않는다(제자리에서 글만 바뀐다)', (tester) async {
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

    testWidgets('기기 "동작 줄이기" 면 처음부터 제자리 · 다 보인다', (tester) async {
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
