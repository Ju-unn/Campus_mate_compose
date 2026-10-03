import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _detail = CardDetail(
  cardId: 'card-1',
  profile: const CardProfile(profileId: 't1', nickname: '여우비', age: 23),
  survey: List.filled(9, 0.5),
  animalType: AnimalType.cat,
  impressionType: ImpressionType.chic,
  religion: Religion.none,
  isSmoker: false,
  interests: const ['등산'],
  myTraits: const ['유머러스'],
  idealTraits: const ['다정한'],
);

/// 10b · 14c 가 같이 쓰는 카드 본문. 14c 전용 부분은 슬롯 3개로 꽂는다(결정: 통합대장 09-27, pen `VTX3D` 기준).
void main() {
  const header = Key('header');
  const trailing = Key('trailing');
  const footer = Key('footer');

  Future<Rect> pump(WidgetTester tester, ProfileCard card) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [universityLogosProvider.overrideWith((ref) => const <String, String>{})],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 328, child: card)),
          ),
        ),
      ),
    ));
    return tester.getRect(find.byType(ProfileCard));
  }

  testWidgets('슬롯은 카드 테두리 안 제자리에 그린다 — 맨 위 · 이름 줄 오른쪽 · 맨 아래', (tester) async {
    final card = await pump(
      tester,
      ProfileCard(
        detail: _detail,
        header: const SizedBox(key: header, width: 120, height: 40),
        nameTrailing: const SizedBox(key: trailing, width: 30, height: 10),
        footer: const SizedBox(key: footer, width: 50, height: 10),
      ),
    );

    // 테두리 1 + 여백 20 안쪽.
    final top = tester.getRect(find.byKey(header));
    expect(top.topLeft, card.topLeft + const Offset(21, 21));
    // 카드는 자리만 내준다 — 머리 칸 크기는 꽂는 쪽이 정하고, 이름 줄은 그 바로 아래다.
    expect(top.size, const Size(120, 40));
    final name = tester.getRect(find.text('여우비, 23'));
    expect(name.top, top.bottom);

    final badge = tester.getRect(find.byKey(trailing));
    expect(badge.right, card.right - 21);
    expect(badge.center.dy, name.center.dy);

    // 맨 아래 칸은 카드 아래 여백까지 가진다 — 14c 링크 줄의 누르는 영역(48)이 여백 안까지 내려가야 한다.
    final bottom = tester.getRect(find.byKey(footer));
    expect(bottom.left, card.left + 21);
    expect(bottom.bottom, card.bottom - 1);
    expect(bottom.top, greaterThan(tester.getRect(find.text('다정한')).bottom));
  });

  testWidgets('슬롯이 없으면 이름은 줄 하나로만 그리고 아래 여백 20 을 카드가 가진다', (tester) async {
    final card = await pump(tester, ProfileCard(detail: _detail));

    expect(tester.getTopLeft(find.text('여우비, 23')), card.topLeft + const Offset(21, 21));
    expect(find.ancestor(of: find.text('여우비, 23'), matching: find.byType(Row)), findsNothing);
    // 마지막 태그 묶음 뒤 섹션 간격 13 + 여백 20 + 테두리 1.
    expect(card.bottom - tester.getRect(find.text('다정한')).bottom, greaterThanOrEqualTo(34));
  });

  testWidgets('학교 줄 `Mz21i` — 졸업모 3D 28 · 간격 8 · 가운데, 글자는 SchoolLabel(로고 붙는 자리)', (tester) async {
    await pump(
      tester,
      ProfileCard(
        detail: CardDetail(
          cardId: 'card-1',
          profile: const CardProfile(
            profileId: 't1',
            nickname: '여우비',
            age: 23,
            university: '테스트대학교',
            major: '컴퓨터공학과',
          ),
          studentNumber: '20',
          survey: List.filled(9, 0.5),
          animalType: AnimalType.cat,
          impressionType: ImpressionType.chic,
          religion: Religion.none,
          isSmoker: false,
          interests: const ['등산'],
          myTraits: const ['유머러스'],
          idealTraits: const ['다정한'],
        ),
      ),
    );

    final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
    expect(label.university, '테스트대학교');
    expect(label.text, '테스트대학교 컴퓨터공학과 20학번');
    final cap = find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.graduationCap);
    expect(tester.widget<Icon3d>(cap).size, 28);
    final capRect = tester.getRect(cap);
    final labelRect = tester.getRect(find.byType(SchoolLabel));
    expect(labelRect.left - capRect.right, 8);
    expect(labelRect.center.dy, capRect.center.dy);
  });
}
