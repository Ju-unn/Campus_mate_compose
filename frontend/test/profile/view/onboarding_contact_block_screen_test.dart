import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/profile/view/onboarding_contact_block_screen.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../safety/model/fake_contact_blocks.dart';

/// 06-4 · 8d · 홈 세 경로만 둔 라우터. 8d 자리는 "차단 끝"(pop true) · "뒤로"(pop) 버튼 둘이다.
Widget _app(FakeDeviceContactSource source) {
  final router = GoRouter(
    initialLocation: AppRoutes.onboardingContactBlock,
    routes: [
      GoRoute(path: AppRoutes.onboardingContactBlock, builder: (context, state) => const OnboardingContactBlockScreen()),
      GoRoute(
        path: AppRoutes.onboardingContactPicker,
        builder: (context, state) => Column(children: [
          TextButton(onPressed: () => context.pop(true), child: const Text('차단 끝')),
          TextButton(onPressed: () => context.pop(), child: const Text('8d 뒤로')),
        ]),
      ),
      GoRoute(path: AppRoutes.home, builder: (context, state) => const Text('홈')),
      GoRoute(path: AppRoutes.onboardingAcquisition, builder: (context, state) => const Text('20d')),
    ],
  );
  return ProviderScope(
    overrides: [deviceContactSourceProvider.overrideWithValue(source)],
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

void main() {
  // pen lK8tn (2026-10-03 값표).
  testWidgets('pen lK8tn: 제목 · 부제 · 안내 · 버튼 · 건너뛰기 · 아래 안내가 보인다', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    // 앱바 제목(x6w7Xd)과 본문 제목(h7ToU) 둘이다.
    expect(find.text('지인 차단'), findsNWidgets(2));
    expect(find.text('아는 사람을 만나고 싶지 않다면 연락처로 미리 막을 수 있어요'), findsOneWidget);
    expect(find.text('연락처 번호는 암호화해서 비교에만 쓰고, 연락처 목록은 저장하지 않아요'), findsOneWidget);
    expect(find.text('연락처에서 지인 차단하기'), findsOneWidget);
    expect(find.text('건너뛰기'), findsOneWidget);
    expect(find.text('나중에 설정 > 지인 차단에서 할 수 있어요'), findsOneWidget);
  });

  testWidgets('pen I8gQZ · Nnsox: 96 원 안에 3D 연락처 52', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    final icon = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.contact);
    expect(tester.getSize(icon), const Size(52, 52));
    final circle = find.ancestor(of: icon, matching: find.byType(Container)).first;
    expect(tester.getSize(circle), const Size(96, 96));
  });

  testWidgets('pen zUojT · Dazi1: 버튼 52, 건너뛰기 48', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    expect(tester.getSize(find.ancestor(of: find.text('연락처에서 지인 차단하기'), matching: find.bySubtype<ButtonStyleButton>())).height, 52);
    expect(tester.getSize(find.widgetWithText(TextButton, '건너뛰기')).height, 48);
  });

  testWidgets('pen x6w7Xd: 앱바 56 · 제목 18/700 · 뒤로는 20d 유입경로로 간다', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    expect(tester.getSize(find.byType(AppBar)).height, 56);
    final title = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.text('지인 차단')));
    expect((title.style?.fontSize, title.style?.fontWeight), (18, FontWeight.w700));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('20d'), findsOneWidget);
  });

  testWidgets('건너뛰기는 홈으로 간다', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('버튼은 온보딩 쪽 8d 를 열고, 차단을 마치면 홈으로 간다', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    await tester.tap(find.text('연락처에서 지인 차단하기'));
    await tester.pumpAndSettle();
    expect(find.text('차단 끝'), findsOneWidget);

    await tester.tap(find.text('차단 끝'));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('8d 에서 차단 없이 돌아오면 06-4 에 머문다', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

    await tester.tap(find.text('연락처에서 지인 차단하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8d 뒤로'));
    await tester.pumpAndSettle();

    expect(find.text('연락처에서 지인 차단하기'), findsOneWidget);
    expect(find.text('홈'), findsNothing);
  });

  testWidgets('권한이 없으면 8a 안내부터 띄운다(8d 로 바로 가지 않는다)', (tester) async {
    await tester.pumpWidget(_app(FakeDeviceContactSource()));

    await tester.tap(find.text('연락처에서 지인 차단하기'));
    await tester.pumpAndSettle();

    expect(find.text('연락처 접근을 허용해 주세요'), findsOneWidget);
    expect(find.text('차단 끝'), findsNothing);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('pen 크기(360×780) 글자 $scale배에서도 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view
        ..physicalSize = const Size(360, 780)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(FakeDeviceContactSource(granted: true)));

      expect(tester.takeException(), isNull);
    });
  }
}
