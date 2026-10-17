import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onBack,
    double textScale = 1,
    bool isBar = false,
    int total = 6,
    Widget? action,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            appBar: OnboardingAppBar(current: 1, total: total, isBar: isBar, onBack: onBack, action: action),
          ),
        ),
      ),
    );
  }

  Finder backButton() => find.widgetWithIcon(IconButton, AppIcons.arrowLeft);

  testWidgets('뒤로 갈 곳이 없으면(onBack 없음 · 쌓인 화면 없음) 화살표 없이 빈 자리만 둔다', (tester) async {
    await pump(tester);

    expect(backButton(), findsNothing);
    expect(find.byTooltip(onboardingBackLabel), findsNothing);
  });

  testWidgets('onBack 을 주면 화살표가 보이고 누르면 그 함수를 부른다', (tester) async {
    var calls = 0;
    await pump(tester, onBack: () => calls++);

    await tester.tap(backButton());

    expect(calls, 1);
  });

  // 앱에 한국어 Material 번역이 없어 MaterialLocalizations 를 쓰면 "Back" 으로 읽힌다(계획서 사실 6).
  testWidgets('화살표는 화면 읽기 프로그램에 "뒤로" 로 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, onBack: () {});

    expect(onboardingBackLabel, '뒤로');
    expect(find.byTooltip('뒤로'), findsOneWidget);
    expect(tester.getSemantics(backButton()), matchesSemantics(
      tooltip: '뒤로',
      isButton: true,
      hasTapAction: true,
      hasFocusAction: true,
      isFocusable: true,
      hasEnabledState: true,
      isEnabled: true,
    ));
    semantics.dispose();
  });

  // pen 앱바 마스터 LTFQg: 안쪽 [0,8], 뒤로 IconButton B8pl1 48×48 · (8,4) · arrow-left 22 #222222.
  testWidgets('화살표는 pen 대로 왼쪽 8 에서 48×48, 아이콘 22 ink 다', (tester) async {
    await pump(tester, onBack: () {});

    final rect = tester.getRect(backButton());
    expect(rect, const Rect.fromLTWH(8, 4, 48, 48));
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft));
    expect((icon.size, icon.color), (22.0, AppColors.ink));
  });

  // 04-1 · 04-4 처럼 화살표가 꺼진 화면에서도 점 묶음 자리가 그대로여야 한다(pen Leading 빈 칸 48).
  testWidgets('화살표가 있든 없든 진행 점 자리는 같다', (tester) async {
    await pump(tester);
    final withoutBack = tester.getRect(find.byType(ProgressDots));

    await pump(tester, onBack: () {});
    final withBack = tester.getRect(find.byType(ProgressDots));

    expect(withBack, withoutBack);
    expect(withBack.center.dx, 180, reason: '360 폭 가운데');
  });

  // pen GCEmW "AppBar · Survey"(05-01~05-11): 360×56 · 안쪽 [0,24,0,8] · 간격 4. 뒤로 B8pl1 (8,4) 48×48 →
  // 진행 막대 IHitX x60 ~ 336(폭 276, 오른쪽 빈 칸 없이 안쪽 24) · 높이 5 · 바탕 #DDDDDD · 채움 #FF385C.
  testWidgets('막대형(GCEmW)은 오른쪽 빈 칸 없이 막대가 x60 ~ 336, 높이 5, 바탕 hairline · 채움 primary', (tester) async {
    await pump(tester, onBack: () {}, isBar: true);

    expect(tester.getRect(backButton()), const Rect.fromLTWH(8, 4, 48, 48));
    final bar = tester.getRect(find.byType(LinearProgressIndicator));
    expect((bar.left, bar.right, bar.height), (60.0, 336.0, 5.0));
    final indicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect((indicator.backgroundColor, indicator.color), (AppColors.hairline, AppColors.primary));
  });

  testWidgets('막대형도 화살표가 꺼진 화면에서 막대 자리는 같다', (tester) async {
    await pump(tester, isBar: true);

    final bar = tester.getRect(find.byType(LinearProgressIndicator));
    expect((bar.left, bar.right), (60.0, 336.0));
  });

  // pen 20d qcQvZ(앱바를 직접 짠 프레임): 뒤로 (8,4) 48×48 · 가운데 빈 칸 x60 w212 · 건너뛰기 k8Mb37 x276 y4 76×48 — 오른쪽 안쪽 8.
  testWidgets('오른쪽 버튼(20d 건너뛰기)은 오른쪽 안쪽 8 — 76×48 이면 (276,4)', (tester) async {
    const actionKey = ValueKey('action');
    await pump(tester, onBack: () {}, total: 0, action: const SizedBox(key: actionKey, width: 76, height: 48));

    expect(tester.getRect(find.byKey(actionKey)), const Rect.fromLTWH(276, 4, 76, 48));
    expect(tester.getRect(backButton()), const Rect.fromLTWH(8, 4, 48, 48));
  });

  testWidgets('글자를 두 배로 키워도 화살표 누름 칸은 48×48 그대로이고 넘치지 않는다', (tester) async {
    await pump(tester, onBack: () {}, textScale: 2);

    expect(tester.getSize(backButton()), const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('위에 쌓인 화면이면 onBack 없이도 화살표가 보이고 누르면 한 장 닫는다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('아래'))));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (context) => const Scaffold(appBar: OnboardingAppBar(current: 2, total: 6)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(backButton());
    await tester.pumpAndSettle();

    expect(find.text('아래'), findsOneWidget);
  });
}
