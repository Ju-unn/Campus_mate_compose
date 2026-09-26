import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// 값은 datingApp.pen 마스터 PccKZ(text-field) · 확인 줄 a1eaV, 04-1 보드 mUUet(2026-09-26 campus-pen 값표).
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? errorText,
    String? successText,
    String? pendingText,
    String? guideText,
    String? helper,
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: LabeledField(
              label: '닉네임',
              errorText: errorText,
              successText: successText,
              pendingText: pendingText,
              guideText: guideText,
              helper: helper,
            ),
          ),
        ),
      ),
    );
  }

  BorderSide enabledSide(WidgetTester tester) {
    final field = tester.widget<TextField>(find.byType(TextField));
    return (field.decoration!.enabledBorder! as OutlineInputBorder).borderSide;
  }

  testWidgets('확인 줄은 입력칸 아래 끝에서 8 떨어진다', (tester) async {
    await pump(tester, successText: '사용할 수 있는 닉네임이에요');
    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    final rowTop = tester.getTopLeft(find.byIcon(AppIcons.circleCheck)).dy;
    // 아이콘은 17 높이 줄 안에서 세로 가운데라 줄 위 끝보다 1.5 아래에 있다.
    expect(rowTop - fieldBottom, closeTo(8 + (17 - 14) / 2, 1));
  });

  testWidgets('사용 가능 표식은 동그라미 체크다', (tester) async {
    await pump(tester, successText: '사용할 수 있는 닉네임이에요');
    expect(find.byIcon(AppIcons.circleCheck), findsOneWidget);
    expect(find.byIcon(AppIcons.check), findsNothing);
  });

  testWidgets('오류가 있으면 입력칸 테두리가 빨간 2px 다', (tester) async {
    await pump(tester, errorText: '이미 있는 닉네임이에요');
    expect(enabledSide(tester), const BorderSide(color: AppColors.error, width: 2));
  });

  testWidgets('확인 중·사용 가능이면 테두리는 기본 1px 그대로다', (tester) async {
    await pump(tester, pendingText: '확인 중…');
    expect(enabledSide(tester), const BorderSide(color: AppColors.outline));
    await pump(tester, successText: '사용할 수 있는 닉네임이에요');
    expect(enabledSide(tester), const BorderSide(color: AppColors.outline));
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서도 확인 줄 글자가 잘리지 않는다', (tester) async {
      await pump(tester, errorText: '한글 또는 영문 2~5자로 입력해 주세요', textScale: scale);
      expect(tester.takeException(), isNull);
      final text = find.text('한글 또는 영문 2~5자로 입력해 주세요');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getSize(text).height, greaterThanOrEqualTo(12 * scale));
    });
  }

  testWidgets('쓰는 도중 안내는 확인 줄 자리(아래 8)에 아이콘 없이 회색으로, 칸 왼쪽 끝에서 시작한다', (tester) async {
    await pump(tester, guideText: '10자 이상 입력해 주세요');
    final field = tester.getRect(find.byType(TextField));
    final text = find.text('10자 이상 입력해 주세요');
    expect(tester.getTopLeft(text).dy - field.bottom, closeTo(8, 1));
    expect(tester.getTopLeft(text).dx, field.left);
    expect(find.byType(Icon), findsNothing);
    expect(tester.widget<Text>(text).style!.color, AppColors.muted);
    expect(enabledSide(tester), const BorderSide(color: AppColors.outline));
  });

  testWidgets('오류가 있으면 쓰는 도중 안내 대신 오류를 보여준다', (tester) async {
    await pump(tester, errorText: '10자 이상 입력해 주세요', guideText: '10자 이상 입력해 주세요');
    expect(find.byIcon(AppIcons.circleAlert), findsOneWidget);
    expect(find.text('10자 이상 입력해 주세요'), findsOneWidget);
  });

  testWidgets('도움말은 입력칸 바로 아래(간격 0)에 붙는다', (tester) async {
    await pump(tester, helper: '숫자 4자리');
    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    expect(tester.getTopLeft(find.text('숫자 4자리')).dy, closeTo(fieldBottom, 0.5));
  });

  // 도움말 간격이 바뀐 출생연도·전화번호 칸(04-1 MLJum·EKXNe)과 06-2a 쓰는 도중 안내.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    for (final (name, helper, guide) in [
      ('출생연도 도움말', '숫자 4자리', null),
      ('전화번호 도움말', '다른 사람이 나를 지인으로 등록했을 때만 사용돼요', null),
      ('쓰는 도중 안내', null, '10자 이상 입력해 주세요'),
    ]) {
      testWidgets('글자 배율 $scale 에서도 $name 글자가 잘리지 않는다', (tester) async {
        await pump(tester, helper: helper, guideText: guide, textScale: scale);
        expect(tester.takeException(), isNull);
        final text = find.text((helper ?? guide)!);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.getSize(text).height, greaterThanOrEqualTo(12 * scale));
      });
    }
  }
}
