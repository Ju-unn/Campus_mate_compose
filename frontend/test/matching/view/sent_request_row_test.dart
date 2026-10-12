import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/sent_request.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/sent_request_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보낸 신청 행(pen 마스터 `SentRequestRow` d6otzp — 값은 대장이 pen 에서 읽어 준 것: 아바타–정보 12 · 정보–상태 12 · 정보 세로 3 · 칩 글자 12/1.25).
SentRequest _request(
  SentRequestStatus status, {
  int? daysLeft,
  String? matchId,
  String nickname = '여우비',
  String major = '컴퓨터공학과',
}) =>
    SentRequest(
      cardId: 'card-1',
      status: status,
      daysLeft: daysLeft,
      matchId: matchId,
      profile: CardProfile(nickname: nickname, age: 23, university: '테스트대학교', major: major),
    );

void main() {
  final opened = <String>[];

  setUp(opened.clear);

  Future<void> pump(WidgetTester tester, SentRequest request, {double width = 328}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [universityLogosProvider.overrideWith((ref) => const <String, String>{})],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: SentRequestRow(request: request, onOpenChat: opened.add)),
            ),
          ),
        ),
      ),
    );
  }

  /// 칩 = 칩 글자를 감싼 가장 가까운 Container(배경 · 모서리를 칠한다).
  Finder chipOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(Container)).first;

  BoxDecoration decorationOf(WidgetTester tester, String label) =>
      tester.widget<Container>(chipOf(label)).decoration! as BoxDecoration;

  Color? textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

  Icon iconIn(WidgetTester tester, String label) =>
      tester.widget<Icon>(find.descendant(of: chipOf(label), matching: find.byType(Icon)));

  group('상태 칩 — 글자 · 아이콘 · 색(대장이 준 pen 값)', () {
    final cases = <(SentRequest, String, IconData, Color, Color)>[
      (_request(SentRequestStatus.waiting, daysLeft: 7), '7일 남음', AppIcons.timer, AppColors.surfaceStrong, AppColors.muted),
      (_request(SentRequestStatus.waiting, daysLeft: 2), '2일 남음', AppIcons.timer, AppColors.surfaceStrong, AppColors.muted),
      // 서버 days_left 는 남은 시간의 올림이라 1 이면 24시간 이하다 — "1일 남음" 은 쓰지 않는다(대장 정정 10-13).
      (_request(SentRequestStatus.waiting, daysLeft: 1), '오늘 마감', AppIcons.timer, AppColors.surfaceStrong, AppColors.muted),
      (_request(SentRequestStatus.matched, matchId: 'm-1'), '매칭됨', AppIcons.messageCircle, AppColors.primaryWash, AppColors.primaryText),
      (_request(SentRequestStatus.rejected), '거절됨', AppIcons.x, AppColors.surfaceStrong, AppColors.muted),
      (_request(SentRequestStatus.expired), '만료됨', AppIcons.timerOff, AppColors.surfaceStrong, AppColors.muted),
    ];
    for (final (request, label, icon, background, foreground) in cases) {
      testWidgets('$label: 아이콘 12 · 글자 12/700/줄높이 1.25 · 배경 · 글자색', (tester) async {
        await pump(tester, request);

        final decoration = decorationOf(tester, label);
        expect(decoration.color, background);
        expect(decoration.borderRadius, BorderRadius.circular(9999));
        final chipIcon = iconIn(tester, label);
        expect(chipIcon.icon, icon);
        expect(chipIcon.size, 12);
        expect(chipIcon.color, foreground);
        final style = tester.widget<Text>(find.text(label)).style!;
        expect(style.fontSize, 12);
        expect(style.height, 1.25);
        expect(style.fontWeight, FontWeight.w700);
        expect(style.color, foreground);
      });
    }
  });

  testWidgets('"1일 남음" 은 어떤 경우에도 보이지 않는다', (tester) async {
    await pump(tester, _request(SentRequestStatus.waiting, daysLeft: 1));

    expect(find.text('1일 남음'), findsNothing);
    expect(find.text('오늘 마감'), findsOneWidget);
  });

  testWidgets('칩은 높이 28 · 좌우 10 · 아이콘과 글자 사이 4 이고 폭은 글자에 맞춘다(72 고정 아님)', (tester) async {
    await pump(tester, _request(SentRequestStatus.rejected));

    final chip = tester.getRect(chipOf('거절됨'));
    final icon = tester.getRect(find.descendant(of: chipOf('거절됨'), matching: find.byType(Icon)));
    final text = tester.getRect(find.text('거절됨'));
    expect(chip.height, 28);
    expect(icon.left - chip.left, 10);
    expect(chip.right - text.right, 10);
    expect(text.left - icon.right, 4);
    expect(chip.width, 10 + 12 + 4 + text.width + 10);
  });

  testWidgets('행은 높이 72 · 배경 없음 · 좌우 여백 없음, 아바타 44 원형', (tester) async {
    await pump(tester, _request(SentRequestStatus.waiting, daysLeft: 3));

    final row = tester.getRect(find.byType(SentRequestRow));
    expect(row.height, 72);
    final avatar = tester.getRect(find.byType(RowAvatar));
    expect(avatar.size, const Size(44, 44));
    expect(avatar.left, row.left);
    expect(tester.getRect(chipOf('3일 남음')).right, row.right);
    // 행 자체에는 바탕색이 없다(받은 신청 행의 분홍 바탕과 다르다).
    expect(find.descendant(of: find.byType(SentRequestRow), matching: find.byType(ColoredBox)), findsNothing);
  });

  testWidgets('아바타–정보 12 · 정보–상태 12, 이름과 학교 줄 사이 3, 모두 세로 가운데', (tester) async {
    await pump(tester, _request(SentRequestStatus.waiting, daysLeft: 3));

    final avatar = tester.getRect(find.byType(RowAvatar));
    final name = tester.getRect(find.text('여우비, 23'));
    final school = tester.getRect(find.byType(SchoolLabel));
    final chip = tester.getRect(chipOf('3일 남음'));
    expect(name.left - avatar.right, 12);
    expect(school.top - name.bottom, 3);
    // 정보 칸은 fill 이라 상태 칸(칩) 바로 왼쪽 12 까지 차지한다.
    final info = tester.getRect(find.ancestor(of: find.text('여우비, 23'), matching: find.byType(Expanded)).first);
    expect(chip.left - info.right, 12);
    final row = tester.getRect(find.byType(SentRequestRow));
    expect(chip.center.dy, row.center.dy);
    expect((name.top + school.bottom) / 2, closeTo(row.center.dy, 0.5));
  });

  testWidgets('이름은 "닉네임, 나이" 16/600 · 학교 줄은 SchoolLabel 14 muted', (tester) async {
    await pump(tester, _request(SentRequestStatus.waiting, daysLeft: 3));

    final name = tester.widget<Text>(find.text('여우비, 23')).style!;
    expect(name.fontSize, 16);
    expect(name.fontWeight, FontWeight.w600);
    expect(name.color, AppColors.ink);
    final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
    expect(label.university, '테스트대학교');
    expect(label.text, '테스트대학교 · 컴퓨터공학과');
    expect(label.style.fontSize, 14);
    expect(label.style.color, AppColors.muted);
  });

  testWidgets('거절됨 · 만료됨은 이름이 muted, 기다리는 중 · 매칭됨은 ink', (tester) async {
    for (final (request, color) in [
      (_request(SentRequestStatus.rejected), AppColors.muted),
      (_request(SentRequestStatus.expired), AppColors.muted),
      (_request(SentRequestStatus.waiting, daysLeft: 3), AppColors.ink),
      (_request(SentRequestStatus.matched, matchId: 'm-1'), AppColors.ink),
    ]) {
      await pump(tester, request);
      expect(textColor(tester, '여우비, 23'), color, reason: request.status.name);
    }
  });

  testWidgets('만료됨은 칩 아래 4 에 "응답이 없었어요" 12/400 muted 를 오른쪽에 맞춰 둔다', (tester) async {
    await pump(tester, _request(SentRequestStatus.expired));

    final chip = tester.getRect(chipOf('만료됨'));
    final note = tester.getRect(find.text('응답이 없었어요'));
    expect(note.top - chip.bottom, 4);
    expect(note.right, chip.right);
    final style = tester.widget<Text>(find.text('응답이 없었어요')).style!;
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.color, AppColors.muted);
  });

  testWidgets('만료됨이 아니면 "응답이 없었어요" 가 없다', (tester) async {
    await pump(tester, _request(SentRequestStatus.rejected));

    expect(find.text('응답이 없었어요'), findsNothing);
  });

  group('눌림 — 매칭됨이고 방이 있을 때만', () {
    testWidgets('매칭됨 + 방: 칩 오른쪽 4 에 chevron 20 primaryText, 누르면 그 방을 연다', (tester) async {
      await pump(tester, _request(SentRequestStatus.matched, matchId: 'm-1'));

      final chevron = find.byIcon(AppIcons.chevronRight);
      expect(chevron, findsOneWidget);
      final icon = tester.widget<Icon>(chevron);
      expect(icon.size, 20);
      expect(icon.color, AppColors.primaryText);
      expect(tester.getRect(chevron).left - tester.getRect(chipOf('매칭됨')).right, 4);

      await tester.tap(find.byType(SentRequestRow));
      expect(opened, ['m-1']);
    });

    testWidgets('눌림 효과는 행 안의 투명 Material 이 그린다 — 화면 전체가 아니다(COMMON §4-2)', (tester) async {
      await pump(tester, _request(SentRequestStatus.matched, matchId: 'm-1'));

      final inkWell = find.byType(InkWell);
      final material = find.ancestor(of: inkWell, matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(inkWell));
      expect(tester.widget<Material>(material).type, MaterialType.transparency);
      expect(tester.getSize(inkWell), tester.getSize(find.byType(SentRequestRow)));
    });

    for (final request in [
      _request(SentRequestStatus.matched),
      _request(SentRequestStatus.waiting, daysLeft: 3),
      _request(SentRequestStatus.rejected),
      _request(SentRequestStatus.expired),
    ]) {
      testWidgets('${request.status.name}${request.matchId == null ? '(방 없음)' : ''}: InkWell 도 chevron 도 없다', (tester) async {
        await pump(tester, request);

        expect(find.descendant(of: find.byType(SentRequestRow), matching: find.byType(InkWell)), findsNothing);
        expect(find.byIcon(AppIcons.chevronRight), findsNothing);
        await tester.tap(find.byType(SentRequestRow), warnIfMissed: false);
        expect(opened, isEmpty);
      });
    }
  });

  testWidgets('이름 · 학교 줄은 한 줄 말줄임이다 — 상태 칸이 정보 칸 폭을 줄인다', (tester) async {
    await pump(
      tester,
      _request(SentRequestStatus.expired, nickname: '아주아주아주아주긴닉네임입니다', major: '아주아주아주아주아주긴학과이름학부전공'),
      width: 328,
    );

    expect(tester.takeException(), isNull);
    final name = tester.widget<Text>(find.text('아주아주아주아주긴닉네임입니다, 23'));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    final school = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
    expect(school.maxLines, 1);
    expect(school.overflow, TextOverflow.ellipsis);
    // 정보 칸은 상태 칸 왼쪽에서 끝난다.
    expect(tester.getRect(find.text('아주아주아주아주긴닉네임입니다, 23')).right,
        lessThanOrEqualTo(tester.getRect(find.text('응답이 없었어요')).left));
  });

  for (final scale in [1.3, 2.0]) {
    for (final request in [
      _request(SentRequestStatus.waiting, daysLeft: 1),
      _request(SentRequestStatus.matched, matchId: 'm-1'),
      _request(SentRequestStatus.expired),
    ]) {
      testWidgets('글자 배율 $scale · ${request.status.name}: 넘치거나 조용히 잘리는 글자가 없다', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pump(tester, request);

        expect(tester.takeException(), isNull);
        // 칩 · 만료 안내 · 이름은 높이가 글자를 따라 커져야 한다(고정 28 · 72 에 갇히면 잘린다).
        for (final paragraph in tester.renderObjectList<RenderParagraph>(find.descendant(
          of: find.byType(SentRequestRow),
          matching: find.byType(RichText),
        ))) {
          expect(paragraph.size.height, greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.5),
              reason: paragraph.text.toPlainText());
        }
        expect(tester.getSize(find.byType(SentRequestRow)).height, greaterThanOrEqualTo(72));
      });
    }
  }
}
