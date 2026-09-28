import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/progress_dots.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/profile/model/acquisition_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/view/acquisition_screen.dart';
import 'package:campus_mate/profile/viewmodel/acquisition_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_acquisition_repository.dart';

/// 20 · 20d · 홈 세 경로만 둔 라우터. 20 과 홈 자리는 글자 하나다.
Widget _app(FakeAcquisitionRepository repository) {
  final router = GoRouter(
    initialLocation: AppRoutes.onboardingAcquisition,
    routes: [
      GoRoute(path: AppRoutes.onboardingAcquisition, builder: (context, state) => const AcquisitionScreen()),
      GoRoute(path: AppRoutes.onboardingReferral, builder: (context, state) => const Text('20')),
      GoRoute(path: AppRoutes.home, builder: (context, state) => const Text('home')),
    ],
  );
  return ProviderScope(
    overrides: [acquisitionRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
  );
}

Finder _start() => find.widgetWithText(AppButton, '시작하기');

void main() {
  testWidgets('헤드라인과 칩 다섯 개가 보이고, 처음엔 시작하기가 꺼져 있다', (tester) async {
    await tester.pumpWidget(_app(FakeAcquisitionRepository()));

    expect(find.text('CampusMate를 어떻게 알게 되셨나요?'), findsOneWidget);
    for (final label in ['에브리타임', '인스타그램', '친구 소개', '커뮤니티', '기타']) {
      expect(find.widgetWithText(SelectChip, label), findsOneWidget);
    }
    expect(tester.widget<AppButton>(_start()).onPressed, isNull);
  });

  // pen uPNnZ (2026-09-28 값표).
  testWidgets('pen uPNnZ: 부제 · 진행 점 없는 앱바 · 바탕 없는 건너뛰기 · 기타 라벨', (tester) async {
    await tester.pumpWidget(_app(FakeAcquisitionRepository()));

    expect(find.text('하나만 골라주세요.\n더 많은 학교에 알리는 데 참고할게요.'), findsOneWidget);
    // 앱바 가운데는 빈 자리(O7JBZ)다 — 진행 점을 그리지 않는다.
    expect(tester.widget<ProgressDots>(find.byType(ProgressDots)).total, 0);
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    expect(tester.getSize(skip).height, 48);
    expect(tester.widget<TextButton>(skip).style?.backgroundColor?.resolve({}), isNull);

    await tester.tap(find.text('기타'));
    await tester.pump();
    expect(find.text('어디서 알게 되셨나요?'), findsOneWidget);
  });

  testWidgets('pen LoyFK: 뒤로가기는 20 추천 코드로 간다', (tester) async {
    await tester.pumpWidget(_app(FakeAcquisitionRepository()));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('기타를 눌러야 입력칸이 보인다', (tester) async {
    await tester.pumpWidget(_app(FakeAcquisitionRepository()));
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('기타'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('기타 글은 30자까지만 들어간다', (tester) async {
    await tester.pumpWidget(_app(FakeAcquisitionRepository()));
    await tester.tap(find.text('기타'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '가' * 31);
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '가' * acquisitionNoteMaxLength);
  });

  testWidgets('칩을 고르고 시작하기를 누르면 저장하고 홈으로 간다', (tester) async {
    final repository = FakeAcquisitionRepository();
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.text('인스타그램'));
    await tester.pump();
    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(repository.submitted, (AcquisitionChannel.instagram, null));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('저장이 실패하면 문구를 보여 주고 머문다', (tester) async {
    final repository = FakeAcquisitionRepository()..nextResult = const FailureResult(NetworkFailure());
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.text('친구 소개'));
    await tester.pump();
    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('건너뛰기는 저장 없이 홈으로 간다', (tester) async {
    final repository = FakeAcquisitionRepository();
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(repository.submitted, isNull);
  });

  testWidgets('칩의 가장 가까운 Material 이 칩 크기다(§4-2)', (tester) async {
    await tester.pumpWidget(_app(FakeAcquisitionRepository()));

    final ink = find.descendant(of: find.widgetWithText(SelectChip, '커뮤니티'), matching: find.byType(InkWell));
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;

    expect(tester.getSize(material), tester.getSize(ink));
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('pen 크기(360×780) 글자 $scale배에서도 기타 입력까지 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view
        ..physicalSize = const Size(360, 780)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(FakeAcquisitionRepository()));
      await tester.tap(find.text('기타'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
