import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const icon = Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk);

  Future<void> pumpToast(WidgetTester tester, String label, {double? width}) async {
    final toast = AppToast(leading: icon, label: label);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: width == null ? toast : SizedBox(width: width, child: toast))),
    ));
  }

  // 한 줄 토스트(04-2 photos_screen · 04-3 avatar_source_screen). 폭은 Flexible 을 더하기 전에 잰 값과 같아야 하고,
  // 높이는 pen Toast 마스터 `I8UOWm` 렌더 40(글자 20)이다 — 고치기 전에는 글자 줄높이 1.2 라 37(글자 17)이었다.
  // 폭 기준값: 2026-09-27 고치기 전 같은 조건(800×600, 기본 배율)에서 잰 크기.
  for (final probe in [
    (label: '1장은 얼굴이 보이지 않아 빠졌어요', toast: const Size(326.75, 40), text: const Size(270.75, 20)),
    (label: '아바타는 만드는 동안 다음 질문을 이어 가요', toast: const Size(398, 40), text: const Size(342, 20)),
  ]) {
    testWidgets('한 줄 토스트는 폭·자리는 전과 같고 높이는 pen 40 이다 — ${probe.label}', (tester) async {
      await pumpToast(tester, probe.label);

      final toast = tester.getRect(find.byType(AppToast));
      final text = tester.getRect(find.text(probe.label));
      expect(toast.width, closeTo(probe.toast.width, 0.01));
      expect(toast.height, closeTo(probe.toast.height, 0.01));
      expect(text.width, closeTo(probe.text.width, 0.01));
      expect(text.height, closeTo(probe.text.height, 0.01));
      // 여백 16 + 그림 16 + 간격 8 = 글자는 왼쪽에서 40, 위에서 10.
      expect(text.left - toast.left, closeTo(40, 0.01));
      expect(text.top - toast.top, closeTo(10, 0.01));
    });
  }

  testWidgets('글자가 토스트 폭을 넘으면 넘치지 않고 줄을 바꾼다', (tester) async {
    // 신고 완료 토스트(pen `yEDB9` 288 폭)처럼 두 줄로 내려가는 문구.
    await pumpToast(tester, '신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요.', width: 288);

    expect(tester.takeException(), isNull);
    final text = tester.getSize(find.text('신고했어요. 이 사용자는 차단되어 서로에게 보이지 않아요.'));
    expect(text.width, lessThanOrEqualTo(288 - 16 * 2 - 16 - 8));
    // pen `yEDB9` 두 줄 렌더 232×40, 토스트 60.
    expect(text.height, 40);
    expect(tester.getSize(find.byType(AppToast)).height, 60);
  });

  testWidgets('leading 이 없으면 글자만 그리고 앞 간격도 없다(15d-3)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: AppToast(label: '하트 10개를 받았어요'))));

    // 안쪽 여백 16 만 — 16 칸 그림 자리 + 간격 8 이 남아 있으면 40 이 된다.
    final toast = tester.getRect(find.byType(AppToast));
    final label = tester.getRect(find.text('하트 10개를 받았어요'));
    expect(label.left - toast.left, AppSpacing.md);
    expect(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)), findsNothing);
  });
}
