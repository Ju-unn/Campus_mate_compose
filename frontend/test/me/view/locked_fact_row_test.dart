import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/me/view/locked_fact_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 마스터 `72. ProfileFactRow · Locked`(`lhrPu`) — 296×48, 라벨 14/normal muted · 값 14/600 disabled · lock 16 disabled, 가로 gap 10.
void main() {
  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: Center(
              child: SizedBox(width: 296, child: LockedFactRow(label: '출생연도', value: '2001')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('높이 48 · 라벨은 왼쪽 · 값 다음 10 뒤에 자물쇠가 오른쪽 끝(`lhrPu`)', (tester) async {
    await pump(tester);

    expect(tester.getSize(find.byType(LockedFactRow)), const Size(296, 48));
    final row = tester.getRect(find.byType(LockedFactRow));
    expect(tester.getTopLeft(find.text('출생연도')).dx, row.left);
    final lock = tester.getRect(find.byIcon(AppIcons.lock));
    expect(lock.size, const Size(16, 16));
    expect(lock.right, row.right);
    expect(lock.left - tester.getRect(find.text('2001')).right, 10);
    expect(tester.getCenter(find.text('2001')).dy, closeTo(row.center.dy, 1));
  });

  testWidgets('라벨 14/400 muted · 값 14/600 disabled · 자물쇠 disabled', (tester) async {
    await pump(tester);

    final label = tester.widget<Text>(find.text('출생연도')).style!;
    expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w400, AppColors.muted));
    final value = tester.widget<Text>(find.text('2001')).style!;
    expect((value.fontSize, value.fontWeight, value.color), (14, FontWeight.w600, AppColors.disabled));
    expect(tester.widget<Icon>(find.byIcon(AppIcons.lock)).color, AppColors.disabled);
  });

  testWidgets('글자를 2.0 배로 키워도 넘치지 않고 높이는 48 이상이다', (tester) async {
    await pump(tester, scale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LockedFactRow)).height, greaterThanOrEqualTo(48));
  });
}
