import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _acceptance = Acceptance(
  cardId: 'c1',
  profile: CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
);

/// 수락 대기 행(pen `XCN1f` → 2026-10-16 `wwfFX`). 결정은 프로필을 본 뒤에 한다 — 행에는 "프로필 보기" 하나뿐이다.
void main() {
  var opened = 0;

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    opened = 0;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [universityLogosProvider.overrideWith((ref) => const <String, String>{})],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 780), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              // 대화 탭처럼 세로로 끝없는 목록 안, 좌우 여백 16 안에 선다.
              body: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [AcceptanceRow(acceptance: _acceptance, onViewProfile: () => opened += 1)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('학교 줄 = SchoolLabel(학교로 로고를 찾고 "학교 · 학과" 를 그린다)', (tester) async {
    await pump(tester);

    final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
    expect(label.university, '테스트대학교');
    expect(label.text, '테스트대학교 · 컴퓨터공학과');
    expect(label.style.fontSize, 14);
    expect(label.style.color, const Color(0xFF6A6A6A));
  });

  testWidgets('버튼은 "프로필 보기" 하나 — 거절 · 수락하기는 행에 없다(pen `wwfFX`)', (tester) async {
    await pump(tester);

    expect(find.byType(AppButton), findsOneWidget);
    expect(find.text('프로필 보기'), findsOneWidget);
    expect(find.text('거절'), findsNothing);
    expect(find.text('수락하기'), findsNothing);
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.variant, AppButtonVariant.primary);
  });

  // 행 높이 130(pen `wwfFX`)은 Pretendard 기준이다 — 시험 글꼴은 글자 줄 높이가 달라 숫자 대신 짜임을 본다:
  // 위 12 · 정보 줄 · 8 · 버튼 44 · 아래 12. 종전 두 버튼 줄도 높이 44 라 행 높이는 바뀌지 않는다.
  testWidgets('"프로필 보기" 는 행 안쪽 폭 전체 × 44, 정보 줄 아래 8 · 행 아래 12 — 행 짜임(높이) 그대로', (tester) async {
    await pump(tester);

    final row = tester.getRect(find.byType(AcceptanceRow));
    // 보이는 버튼 = ElevatedButton 의 Material(누르는 칸은 위아래 2씩 더 큰 48 — 종전 두 버튼 줄과 같다).
    final button = tester.getRect(find.descendant(of: find.byType(AppButton), matching: find.byType(Material)).first);
    // 정보 줄 = 아바타 44 와 이름 · 학교 두 줄을 담은 Row(아바타는 그 안에서 세로 가운데).
    final info = tester.getRect(find.ancestor(of: find.byType(RowAvatar), matching: find.byType(Row)).first);
    expect(button.width, row.width - 24);
    expect(button.left, row.left + 12);
    expect(button.height, 44);
    expect(button.top - info.bottom, 8 + 2);
    expect(row.bottom - button.bottom, 12 + 2);
    expect(info.top - row.top, 12);
  });

  testWidgets('"프로필 보기" 를 누르면 onViewProfile 이 한 번 불린다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('프로필 보기'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('낭독기에는 "프로필 보기" 버튼으로 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final node = tester.getSemantics(find.byType(AppButton));
    expect(node.label, '프로필 보기');
    expect(node.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서 행이 넘치거나 글자가 잘리지 않는다', (tester) async {
      await pump(tester, scale: scale);

      expect(tester.takeException(), isNull);
      for (final element in find.byType(RichText).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(paragraph.size.height, greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.5),
            reason: paragraph.text.toPlainText());
      }
    });
  }
}
