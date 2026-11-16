import 'package:campus_mate/common/widgets/app_checkbox.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(bool checked, {bool reduceMotion = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Center(child: AppCheckbox(checked: checked)),
        ),
      ),
    );

BoxDecoration _box(WidgetTester tester) => tester
    .widget<Container>(find.descendant(of: find.byType(AppCheckbox), matching: find.byType(Container)).first)
    .decoration! as BoxDecoration;

/// 체크 표시가 지금 보이는 정도(겹친 투명도의 곱).
double _check(WidgetTester tester) {
  var value = 1.0;
  for (final fade in tester.widgetList<FadeTransition>(
    find.ancestor(of: find.byIcon(AppIcons.check), matching: find.byType(FadeTransition)),
  )) {
    value *= fade.opacity.value;
  }
  return value;
}

void main() {
  // 사용자 2026-11-16 「체크박스 ease in out 부드럽게」 — 시간은 원문에 없어 standard(220ms)에 맞췄다.
  testWidgets('켜면 220ms 동안 easeInOut 으로 채움이 primary 가 되고 체크가 나타난다', (tester) async {
    await tester.pumpWidget(_host(false));
    await tester.pumpWidget(_host(true));
    expect(_box(tester).color, isSameColorAs(AppColors.canvas));
    expect(_check(tester), 0);

    await tester.pump(AppMotion.checkbox ~/ 2);
    final t = Curves.easeInOut.transform(0.5);
    expect(_box(tester).color, isSameColorAs(Color.lerp(AppColors.canvas, AppColors.primary, t)!));
    expect(_check(tester), closeTo(t, 1e-6));

    await tester.pump(AppMotion.checkbox ~/ 2);
    expect(_box(tester).color, AppColors.primary);
    expect(_box(tester).border, isNull);
    expect(_check(tester), 1);
    expect(tester.getSize(find.byIcon(AppIcons.check)), const Size(16, 16));
  });

  testWidgets('끄면 같은 시간 · 커브로 돌아가고 체크는 흐려지며 사라진다', (tester) async {
    await tester.pumpWidget(_host(true));
    await tester.pumpWidget(_host(false));
    await tester.pump(AppMotion.checkbox ~/ 2);
    final t = Curves.easeInOut.transform(0.5);
    expect(_box(tester).color, isSameColorAs(Color.lerp(AppColors.primary, AppColors.canvas, t)!));
    expect(_check(tester), closeTo(1 - t, 1e-6));

    // Flutter 애니메이션은 시간을 "넘긴" 첫 장면에서 끝난다.
    await tester.pump(AppMotion.checkbox ~/ 2 + const Duration(milliseconds: 1));
    expect(_box(tester).color, AppColors.canvas);
    expect(_box(tester).border, Border.all(color: AppColors.outline, width: 1.5));
    expect(find.byIcon(AppIcons.check), findsNothing);
  });

  testWidgets('기기 "동작 줄이기" 면 바로 바뀐다', (tester) async {
    await tester.pumpWidget(_host(false, reduceMotion: true));
    await tester.pumpWidget(_host(true, reduceMotion: true));
    expect(_box(tester).color, AppColors.primary);
    expect(_check(tester), 1);
  });

  testWidgets('크기 24 · 모서리 6 은 그대로다(pen ORl5o · zlg4q)', (tester) async {
    await tester.pumpWidget(_host(true));
    expect(tester.getSize(find.byType(AppCheckbox)), const Size(24, 24));
    expect(_box(tester).borderRadius, BorderRadius.circular(6));
  });
}
