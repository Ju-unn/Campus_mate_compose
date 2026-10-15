import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/basic_info_screen.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_basic_info_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  /// 입력칸에 글자가 들어올 때 포매터가 순서대로 도는 것과 같다.
  String typed(List<TextInputFormatter> formatters, String text) {
    var value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    for (final formatter in formatters) {
      value = formatter.formatEditUpdate(TextEditingValue.empty, value);
    }
    return value.text;
  }

  test('닉네임은 한글·영문만 남고 숫자·특수문자·공백은 들어오지 않는다', () {
    expect(typed(nicknameInputFormatters, '홍길동'), '홍길동');
    expect(typed(nicknameInputFormatters, 'Gildong'), 'Gildong');
    expect(typed(nicknameInputFormatters, '홍길동1!@# '), '홍길동');
  });

  test('닉네임은 한글 조합 중의 자모를 막지 않는다', () {
    // 막으면 기기에서 한글 자체를 칠 수 없다 — 자모만 남은 값은 보낼 때 형식 검사가 거른다.
    expect(typed(nicknameInputFormatters, 'ㅎ'), 'ㅎ');
    expect(typed(nicknameInputFormatters, '호ㅇ'), '호ㅇ');
  });

  test('출생연도는 숫자 4자리에서 끊는다', () {
    expect(typed(birthYearInputFormatters, '2003'), '2003');
    expect(typed(birthYearInputFormatters, '20a03년'), '2003');
    expect(typed(birthYearInputFormatters, '20031'), '2003');
  });

  test('키는 숫자 3자리에서 끊는다', () {
    expect(typed(heightInputFormatters, '175'), '175');
    expect(typed(heightInputFormatters, '17cm5'), '175');
    expect(typed(heightInputFormatters, '1750'), '175');
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          basicInfoNowProvider.overrideWithValue(() => DateTime(2026, 6, 1)),
          basicInfoRepositoryProvider.overrideWithValue(FakeBasicInfoRepository()),
          onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        ],
        child: const MaterialApp(home: BasicInfoScreen()),
      ),
    );
  }

  testWidgets('출생연도 칸은 나이가 모자라면 도움말 자리에 "○○년생부터" 오류를 띄운다', (tester) async {
    // 360 폭 기기에서 반 칸에 두 줄로 접혀도 넘치지 않아야 한다.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester);
    final birthYear = find.descendant(
      of: find.widgetWithText(LabeledField, '출생연도 · 필수'),
      matching: find.byType(TextField),
    );

    await tester.enterText(birthYear, '2008');
    await tester.pump();

    expect(find.text('2007년생부터 가입할 수 있어요'), findsOneWidget);
    expect(find.text('숫자 4자리'), findsNothing);

    await tester.enterText(birthYear, '2007');
    await tester.pump();

    expect(find.text('2007년생부터 가입할 수 있어요'), findsNothing);
    expect(find.text('숫자 4자리'), findsOneWidget);
  });

  // 3b 실명 · 3c 학과 · 학번과 같은 "· 필수" 표기. 선택 항목인 내 MBTI 에는 붙이지 않는다.
  testWidgets('필수 항목 라벨 다섯 개에는 "· 필수" 가 붙고 내 MBTI 에는 붙지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester);

    for (final label in ['닉네임 · 필수', '출생연도 · 필수', '키 (cm) · 필수', '전화번호 · 필수', '성별 · 필수']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('내 MBTI'), findsOneWidget);
    expect(find.textContaining('MBTI · 필수'), findsNothing);
  });

  testWidgets('전화번호 칸에 규칙에 걸리는 번호를 다 치면 칸 아래 빨간 한 줄이 뜬다', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester);
    final phone = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '010-0000-0000');

    await tester.enterText(phone, '01012345678');
    await tester.pump();

    expect(find.text('올바른 휴대폰 번호를 입력해 주세요'), findsOneWidget);

    await tester.enterText(phone, '01048217395');
    await tester.pump();

    expect(find.text('올바른 휴대폰 번호를 입력해 주세요'), findsNothing);
  });
}
