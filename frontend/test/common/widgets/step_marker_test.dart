import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/common/widgets/step_marker.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, StepMarkerStatus status) {
  return tester.pumpWidget(
    MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: StepMarker(label: '단계', status: status))),
  );
}

void main() {
  testWidgets('끝난 단계는 초록 체크 아이콘 18, 움직이는 그림은 없다', (tester) async {
    await _pump(tester, StepMarkerStatus.done);

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.circleCheck));
    expect((icon.size, icon.color), (18, AppColors.success));
    expect(find.byType(AppLottieView), findsNothing);
  });

  testWidgets('기다리는 단계는 회색 빈 동그라미 18, 움직이는 그림은 없다', (tester) async {
    await _pump(tester, StepMarkerStatus.wait);

    final icon = tester.widget<Icon>(find.byIcon(AppIcons.circle));
    expect((icon.size, icon.color), (18, AppColors.hairline));
    expect(find.byType(AppLottieView), findsNothing);
  });

  // pen 06-2b `DAV2j` "진행 중" 줄의 스피너 자리 `OPQvA` 22×22 (대장 전달).
  testWidgets('진행 중 단계는 옛 점 아이콘 대신 브랜드 스피너를 22×22 로 돌린다', (tester) async {
    await _pump(tester, StepMarkerStatus.active);

    final spinner = find.byType(AppLottieView);
    expect(spinner, findsOneWidget);
    expect(tester.widget<AppLottieView>(spinner).scene, AppLottie.brandSpinner);
    expect(tester.getSize(spinner), const Size(22, 22));
    expect(find.byIcon(AppIcons.circleDot), findsNothing);
  });

  // pen `DAV2j` 세 줄 모두 아이콘 칸 18×18 이 같은 x, 라벨이 같은 세로줄이다(대장 확인 2026-11-03). 시안 스피너 22×22(`OPQvA`)는
  // 18 칸 가운데에 겹쳐 그린 것(위아래 · 좌우 2씩 넘침) — 칸이 그대로라 진행 중 줄 라벨도 다른 줄과 같은 x 에 선다.
  testWidgets('세 줄의 라벨 x 가 같고, 스피너 22×22 는 18 칸의 가운데에 넘치게 그려진다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StepMarker(label: '끝', status: StepMarkerStatus.done),
              StepMarker(label: '중', status: StepMarkerStatus.active),
              StepMarker(label: '뒤', status: StepMarkerStatus.wait),
            ],
          ),
        ),
      ),
    );

    final labelLefts = [for (final label in ['끝', '중', '뒤']) tester.getRect(find.text(label)).left];
    expect(labelLefts.toSet(), hasLength(1), reason: '$labelLefts');
    final doneIcon = tester.getRect(find.byIcon(AppIcons.circleCheck));
    final spinner = tester.getRect(find.byType(AppLottieView));
    expect(spinner.size, const Size(22, 22));
    expect(spinner.center.dx, doneIcon.center.dx);
    expect(spinner.center.dy, tester.getCenter(find.text('중')).dy);
    // 스피너가 넘쳐도 줄 높이는 아이콘 칸(18) 그대로 — 아래 줄을 밀지 않는다(진행 중 라벨은 14/1.2 라 18 안에 든다).
    expect(tester.getSize(find.byType(StepMarker).at(1)).height, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('스피너 파일을 못 읽으면 옛 점 아이콘으로 대신한다', (tester) async {
    await _pump(tester, StepMarkerStatus.active);

    final fallback = tester.widget<AppLottieView>(find.byType(AppLottieView)).fallback! as Icon;
    expect((fallback.icon, fallback.size, fallback.color), (AppIcons.circleDot, 18, AppColors.primaryText));
  });

  testWidgets('진행 중 줄도 글자는 지금 모양 그대로(ink, 라벨 작은 굵은 글씨)', (tester) async {
    await _pump(tester, StepMarkerStatus.active);

    expect(tester.widget<Text>(find.text('단계')).style?.color, AppColors.ink);
  });
}
