import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/mbti_pole_toggle.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/profile/appearance/view/appearance_pickers.dart';
import 'package:campus_mate/profile/ideal/model/repository/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/ideal/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:campus_mate/profile/onboarding/model/repository/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/onboarding/view/profile_enum_text.dart';
import 'package:campus_mate/profile/traits/view/choice_pickers.dart';
import 'package:campus_mate/profile/traits/viewmodel/survey_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../onboarding/model/repository/fake_onboarding_repository.dart';
import '../model/repository/fake_ideal_conditions_repository.dart';

void main() {
  /// [surveyIsSmoker] 는 바로 앞 설문(05-11)에서 고른 흡연 답이다 — null 이면 아직 안 고른 것.
  Future<void> pump(WidgetTester tester, {bool? surveyIsSmoker}) async {
    final container = ProviderContainer(
      overrides: [
        idealConditionsRepositoryProvider.overrideWithValue(FakeIdealConditionsRepository()),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);
    if (surveyIsSmoker != null) {
      container.read(surveyViewModelProvider.notifier).changeIsSmoker(surveyIsSmoker);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: IdealConditionsScreen()),
      ),
    );
  }

  // 선호 MBTI 안내(2026-11-02 앱 1.0.1, pen 06-1 `QrUdQ` 안내 `MED5L`) — 서버는 축마다 따로 봐서 두 극을 다 골라도 그 축은 상관없다.
  // 안내는 제목 옆이 아니라 칩 묶음 아래다: 섹션 `soTqZ` 세로 gap 8, 12/normal #6A6A6A, 한 줄 자동 폭.
  group('MBTI 안내(pen `MED5L`)', () {
    const hintText = '고르지 않거나 둘 다 고르면 상관없어요.';

    Future<void> pumpAt(WidgetTester tester, {required double textScale}) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
    }

    testWidgets('칩 묶음 아래 8 에 한 줄(12/1.4) 왼쪽 정렬 muted 로 놓이고 제목 줄에는 없다', (tester) async {
      await pumpAt(tester, textScale: 1);

      final hint = find.text(hintText);
      expect(hint, findsOneWidget);
      expect(find.text('선택하지 않으면 상관없어요.'), findsNothing);
      final toggle = find.byType(MbtiPoleToggle);
      expect(tester.getTopLeft(hint).dy - tester.getBottomLeft(toggle).dy, 8); // 칩 아래 간격 8
      expect(tester.getTopLeft(hint).dx, 24); // 화면 좌우 여백
      expect(tester.getSize(hint).height, closeTo(12 * 1.4, 0.5)); // 한 줄(줄 높이는 정수 픽셀로 맞춰져 17)
      final style = tester.widget<Text>(hint).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.muted));
      // 제목 `IhhKP` 줄에는 안내가 없다 — 제목은 글자 하나뿐이다.
      final titleRow = find.ancestor(of: find.text('선호하는 성향 (MBTI)'), matching: find.byType(Row)).first;
      expect(find.descendant(of: titleRow, matching: find.text(hintText)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('글자 1.5배 · 폭 360 에서도 넘치지 않고 화면 안쪽 여백 안이다', (tester) async {
      await pumpAt(tester, textScale: 1.5);

      final hint = find.text(hintText);
      expect(hint, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(hint).right, lessThanOrEqualTo(360 - 24));
      expect(tester.getTopLeft(hint).dy, greaterThan(tester.getBottomLeft(find.byType(MbtiPoleToggle)).dy));
    });
  });

  Future<void> pumpNarrow(WidgetTester tester, {double textScale = 1, bool? surveyIsSmoker}) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, surveyIsSmoker: surveyIsSmoker);
  }

  TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

  // 앱 1.0.2 — 제목 줄 pen 맞추기. 얼굴상 · 인상 머리줄(`u3Dfkd` · `wOFH0`)은 가로 한 줄, 양 끝 정렬, 세로 가운데,
  // 오른쪽 끝에 "1~3개"(`wDKhx` · `MCJ3z` #6A6A6A 12/normal 1.4). 머리줄과 고르기 칸 사이 8.
  group('제목 줄(pen `u3Dfkd` · `wOFH0`)', () {
    for (final (title, picker) in [('선호하는 얼굴상', AnimalTypePicker), ('선호하는 인상', ImpressionTypePicker)]) {
      testWidgets('"$title" 줄은 제목이 왼쪽 끝, "1~3개" 안내가 오른쪽 끝이고 세로 가운데다', (tester) async {
        await pumpNarrow(tester);

        final titleText = find.text(title);
        final row = find.ancestor(of: titleText, matching: find.byType(Row)).first;
        final hint = find.descendant(of: row, matching: find.text('1~3개'));
        expect(hint, findsOneWidget);
        expect(tester.getTopLeft(titleText).dx, 24); // 화면 좌우 여백
        // 안내 칸이 글자 폭만 차지하고(제목 옆에서 늘어난 칸이 아니라) 오른쪽 끝에 닿는다.
        expect(tester.getSize(hint).width, lessThan(60));
        expect(tester.getTopRight(hint).dx, 360 - 24);
        expect(tester.getCenter(hint).dy, closeTo(tester.getCenter(titleText).dy, 0.5)); // 세로 가운데
        final style = tester.widget<Text>(hint).style!;
        expect((style.fontSize, style.fontWeight, style.height, style.color), (12, FontWeight.w400, 1.4, AppColors.muted));
        expect(tester.takeException(), isNull);
      });

      testWidgets('"$title" 머리줄과 고르기 칸 사이는 8 이다', (tester) async {
        await pumpNarrow(tester);

        final row = find.ancestor(of: find.text(title), matching: find.byType(Row)).first;
        expect(tester.getTopLeft(find.byType(picker)).dy - tester.getBottomLeft(row).dy, 8);
      });
    }

    testWidgets('"1~3개" 안내는 얼굴상 · 인상 줄에만 있다', (tester) async {
      await pumpNarrow(tester);

      expect(find.text('1~3개'), findsNWidgets(2));
    });

    testWidgets('제목 색은 여섯 개 모두 #3F3F3F 이고 모두 14/600/1.2 다(사용자 11-04 「1」 — pen `AByJi` · `BaCk1` 도 #3F3F3F 로 맞춤)', (tester) async {
      await pumpNarrow(tester);

      for (final title in ['선호하는 얼굴상', '선호하는 인상', '선호하는 성향 (MBTI)', '선호하는 나이 범위', '선호하는 키 범위', '흡연하는 사람']) {
        expect(styleOf(tester, title).color, AppColors.body, reason: title);
      }
      for (final title in ['선호하는 얼굴상', '선호하는 인상', '선호하는 성향 (MBTI)', '선호하는 나이 범위', '선호하는 키 범위', '흡연하는 사람']) {
        final style = styleOf(tester, title);
        expect((style.fontSize, style.fontWeight, style.height), (14, FontWeight.w600, 1.2), reason: title);
      }
    });
  });

  // 앱 1.0.2 — pen 06-1 `QrUdQ` Scroll Area 맨 끝(키 칸 `v9kNn` 다음)의 Smoking Section `dFTqN`.
  // 섹션 사이 32, 섹션 안 8. 제목 `vCjus` 14/600 #3F3F3F, 두 칸 `Mg9O3`(높이 56 · 칸 사이 12 · 왼쪽 싫어요 · 오른쪽 상관없어요),
  // 설명 `wd83D` 12/normal #6A6A6A lineHeight 1.4.
  group('흡연하는 사람 칸(pen `dFTqN`)', () {
    const description = '싫어요를 고르면 흡연하지 않는 분을 먼저 보여 드려요.';

    Finder cell(String label) => find.ancestor(of: find.text(label), matching: find.byType(ChoiceCell));
    bool isSelected(WidgetTester tester, String label) => tester.widget<ChoiceCell>(cell(label)).isSelected;
    Finder heightIgnoreRow() => find.ancestor(of: find.text('키는 상관없어요'), matching: find.byType(InkWell)).first;

    testWidgets('키 칸 다음 맨 끝에 제목 · 두 칸 · 설명 순서로 있다', (tester) async {
      await pumpNarrow(tester);

      expect(find.text('흡연하는 사람'), findsOneWidget);
      final tops = [
        tester.getBottomLeft(heightIgnoreRow()).dy,
        tester.getTopLeft(find.text('흡연하는 사람')).dy,
        tester.getTopLeft(cell('싫어요')).dy,
        tester.getTopLeft(find.text(description)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
    });

    testWidgets('간격: 키 칸과 32, 제목과 칸 8, 칸 높이 56 · 칸 사이 12 · 가로 2분할, 칸과 설명 8, 화면 여백 24', (tester) async {
      await pumpNarrow(tester);

      final title = find.text('흡연하는 사람');
      final left = cell('싫어요');
      final right = cell('상관없어요');
      expect(tester.getTopLeft(title).dy - tester.getBottomLeft(heightIgnoreRow()).dy, 32); // 섹션 사이
      expect(tester.getTopLeft(left).dy - tester.getBottomLeft(title).dy, 8); // 제목 아래
      expect((tester.getSize(left).height, tester.getSize(right).height), (56, 56));
      expect(tester.getTopLeft(right).dx - tester.getTopRight(left).dx, 12); // 칸 사이
      expect(tester.getSize(left).width, tester.getSize(right).width); // 가로 2분할
      expect((tester.getTopLeft(left).dx, tester.getTopRight(right).dx), (24, 360 - 24));
      expect(tester.getTopLeft(find.text(description)).dy - tester.getBottomLeft(left).dy, 8); // 칸 아래
      expect(tester.getTopLeft(find.text(description)).dx, 24);
    });

    // 줄 수는 단정하지 않는다 — 시험 글꼴(Ahem)은 실제 Pretendard 보다 넓어서 폭 360 에서 두 줄로 접힌다.
    testWidgets('설명은 12/normal muted(줄 높이 1.4)이고 왼쪽 정렬이다', (tester) async {
      await pumpNarrow(tester);

      final text = tester.widget<Text>(find.text(description));
      final style = text.style!;
      expect((style.fontSize, style.fontWeight, style.height, style.color), (12, FontWeight.w400, 1.4, AppColors.muted));
      expect(text.textAlign, anyOf(isNull, TextAlign.start, TextAlign.left));
    });

    testWidgets('글자 1.5배 · 폭 360 에서도 넘치지 않고 설명은 화면 안쪽 여백 안이다', (tester) async {
      await pumpNarrow(tester, textScale: 1.5);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text(description)).right, lessThanOrEqualTo(360 - 24));
    });

    testWidgets('설문에서 "안 한다" 를 골랐으면 싫어요가 골라진 채 열린다', (tester) async {
      await pumpNarrow(tester, surveyIsSmoker: false);

      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (true, false));
    });

    testWidgets('설문에서 "한다" 를 골랐으면 상관없어요가 골라진 채 열린다', (tester) async {
      await pumpNarrow(tester, surveyIsSmoker: true);

      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (false, true));
    });

    testWidgets('설문 답을 모르면 두 칸 다 안 고른 채 열리고, 얼굴상 · 인상만 고르면 흡연 칸을 안 골라도 "다음" 이 눌린다', (tester) async {
      await pumpNarrow(tester);
      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (false, false));

      for (final label in [AnimalType.cat.label(AppLocalizationsKo()), ImpressionType.kind.label(AppLocalizationsKo())]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
      }
      await tester.pump();

      expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (false, false)); // 눌러도 미리 고르지 않는다
    });

    testWidgets('안 고른 채 한 칸을 누르면 그 칸이 켜진다', (tester) async {
      await pumpNarrow(tester);

      await tester.ensureVisible(cell('싫어요'));
      await tester.tap(cell('싫어요'));
      await tester.pump();

      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (true, false));
    });

    testWidgets('두 칸을 누르면 고른 칸이 바뀐다', (tester) async {
      await pumpNarrow(tester, surveyIsSmoker: false);

      await tester.ensureVisible(cell('상관없어요'));
      await tester.tap(cell('상관없어요'));
      await tester.pump();
      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (false, true));

      await tester.tap(cell('싫어요'));
      await tester.pump();
      expect((isSelected(tester, '싫어요'), isSelected(tester, '상관없어요')), (true, false));
    });
  });

  for (final label in ['나이는 상관없어요', '키는 상관없어요']) {
    testWidgets('"$label" 눌림 효과는 화면이 아니라 그 줄이 그린다', (tester) async {
      // 눌림 효과는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 스크롤해도 테두리만
      // 제자리에 떠 있다(2026-09-27 사용자 실기기, COMMON §4-2).
      await pump(tester);

      final text = find.text(label);
      final row = find.ancestor(of: text, matching: find.byType(InkWell)).first;
      final painter = find.ancestor(of: text, matching: find.byType(Material)).first;

      expect(tester.getSize(painter), tester.getSize(row));
    });
  }
}
