import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 수락 대기 행(pen `XCN1f`)의 학교 줄.
void main() {
  testWidgets('학교 줄 = SchoolLabel(학교로 로고를 찾고 "학교 · 학과" 를 그린다)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [universityLogosProvider.overrideWith((ref) => const <String, String>{})],
        child: MaterialApp(
          home: Scaffold(
            body: AcceptanceRow(
              acceptance: const Acceptance(
                cardId: 'c1',
                profile: CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
              ),
              onReject: () {},
              onAccept: () {},
            ),
          ),
        ),
      ),
    );

    final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
    expect(label.university, '테스트대학교');
    expect(label.text, '테스트대학교 · 컴퓨터공학과');
    expect(label.style.fontSize, 14);
    expect(label.style.color, const Color(0xFF6A6A6A));
  });
}
