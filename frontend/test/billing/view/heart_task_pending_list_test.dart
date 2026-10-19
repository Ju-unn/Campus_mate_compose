import 'package:campus_mate/billing/model/heart_task_pending.dart';
import 'package:campus_mate/billing/view/heart_task_pending_list.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pretendard.dart';

/// 18a 검수 대기 블록(pen 18a 대기 1건 pVxvl · 한도 찬 상태 tYwTB — 기존 HeartTaskRow R99dx 줄 아래).
/// 블록: 폭 fill · 세로 gap 8 · padding [8,0,12,40]. 제목 12/600 muted, 줄마다 썸네일 36×36(바탕 #EBEBEB, 모서리 8, 간격 4) ·
/// 제출 시각 12 muted · 배지 "검수중"(SaMDZ Status, 바탕 #F2F2F2, 글자 11/700 muted).
void main() {
  // 시험 기본 글꼴(Ahem)은 글자 폭이 실제와 달라 한 줄이 접힌다 — 실제 글꼴로 pen 치수를 잰다.
  setUpAll(loadPretendard);
  final today = DateTime.now();
  DateTime at(int hour, int minute) => DateTime(today.year, today.month, today.day, hour, minute);

  HeartTaskPending pending(String id, DateTime createdAt, List<String?> urls) =>
      HeartTaskPending(id: id, createdAt: createdAt, photoUrls: urls);

  Future<void> pump(
    WidgetTester tester,
    List<HeartTaskPending> list, {
    String? note,
    double textScale = 1,
    double width = 328,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: HeartTaskPendingList(pending: list, note: note)),
          ),
        ),
      ),
    );
  }

  Finder thumbs() => find.byType(HeartTaskPendingThumb);

  testWidgets('제목 "검수 대기 n건" 12/600 muted — 줄 수만큼', (tester) async {
    await pump(tester, [
      pending('a', at(14, 35), ['u1']),
      pending('b', at(16, 2), ['u2']),
    ]);

    final style = tester.widget<Text>(find.text('검수 대기 2건')).style!;
    expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w600, AppColors.muted));
  });

  testWidgets('블록 안쪽 여백 위 8 · 왼쪽 40 · 아래 12, 제목 → 8 → 첫 줄(썸네일 36)', (tester) async {
    await pump(tester, [
      pending('a', at(14, 20), ['u1', 'u2', 'u3']),
    ]);

    final block = tester.getRect(find.byType(HeartTaskPendingList));
    final title = tester.getRect(find.text('검수 대기 1건'));
    expect((title.left - block.left, title.top - block.top), (40, 8));
    final first = tester.getRect(thumbs().first);
    expect(first.top - title.bottom, 8);
    expect(block.bottom - first.bottom, 12);
  });

  testWidgets('썸네일 3장 — 36×36 · 사이 4 · 모서리 8 · 바탕 #EBEBEB, 사진 주소는 서명 URL 그대로', (tester) async {
    await pump(tester, [
      pending('a', at(14, 20), ['https://signed.test/1', 'https://signed.test/2', 'https://signed.test/3']),
    ]);

    expect(thumbs(), findsNWidgets(3));
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(thumbs().at(i))];
    expect([for (final r in rects) r.size], const [Size(36, 36), Size(36, 36), Size(36, 36)]);
    expect(rects[1].left - rects[0].right, 4);
    expect(rects[2].left - rects[1].right, 4);
    final tile = tester.widget<ClipRRect>(find.descendant(of: thumbs().first, matching: find.byType(ClipRRect)));
    expect(tile.borderRadius, BorderRadius.circular(8));
    final bg = find.descendant(of: thumbs().first, matching: find.byType(ColoredBox));
    expect(tester.widget<ColoredBox>(bg.first).color, AppColors.hairlineSoft);
    final urls = [
      for (final image in tester.widgetList<Image>(find.descendant(of: find.byType(HeartTaskPendingList), matching: find.byType(Image))))
        ((image.image as ResizeImage).imageProvider as NetworkImage).url,
    ];
    expect(urls, ['https://signed.test/1', 'https://signed.test/2', 'https://signed.test/3']);
  });

  testWidgets('서명에 실패한 장(null)은 그림 없이 회색 칸으로 남는다 — 장수는 그대로', (tester) async {
    await pump(tester, [
      pending('a', at(14, 20), ['https://signed.test/1', null, 'https://signed.test/3']),
    ]);

    expect(thumbs(), findsNWidgets(3));
    expect(find.descendant(of: find.byType(HeartTaskPendingList), matching: find.byType(Image)), findsNWidgets(2));
    expect(tester.getSize(thumbs().at(1)), const Size(36, 36));
  });

  testWidgets('사진 주소를 못 받아도(400) 넘침 · 예외 없이 회색 칸이 남는다', (tester) async {
    await pump(tester, [
      pending('a', at(14, 20), ['https://signed.test/broken']),
    ]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(thumbs(), findsOneWidget);
    expect(tester.getSize(thumbs()), const Size(36, 36));
  });

  testWidgets('줄 = 썸네일 → 8 → "오늘 HH:mm 제출" 12 muted, 배지 "검수중" 은 오른쪽 끝 · 바탕 #F2F2F2 · 11/700 muted', (tester) async {
    await pump(tester, [
      pending('a', at(14, 20), ['u1', 'u2', 'u3']),
    ]);

    final time = find.text('오늘 14:20 제출');
    final style = tester.widget<Text>(time).style!;
    expect((style.fontSize, style.color), (12, AppColors.muted));
    expect(tester.getRect(time).left - tester.getRect(thumbs().last).right, 8);
    expect(tester.getCenter(time).dy, closeTo(tester.getCenter(thumbs().first).dy, 1));

    final badge = find.ancestor(of: find.text('검수중'), matching: find.byType(DecoratedBox)).first;
    expect((tester.widget<DecoratedBox>(badge).decoration as BoxDecoration).color, AppColors.surfaceStrong);
    expect(tester.getRect(badge).right, 328);
    expect(tester.getSize(badge).height, 28);
    final label = tester.widget<Text>(find.text('검수중')).style!;
    expect((label.fontSize, label.fontWeight, label.color), (11, FontWeight.w700, AppColors.muted));
    expect(find.byIcon(AppIcons.timer), findsOneWidget);
  });

  testWidgets('줄 사이 8 — 둘째 줄은 한 장이어도 같은 규격', (tester) async {
    await pump(tester, [
      pending('a', at(14, 35), ['u1', 'u2']),
      pending('b', at(16, 2), ['u3']),
    ]);

    expect(thumbs(), findsNWidgets(3));
    expect(tester.getTopLeft(thumbs().at(2)).dy - tester.getBottomLeft(thumbs().at(1)).dy, 8);
    expect(find.text('오늘 14:35 제출'), findsOneWidget);
    expect(find.text('오늘 16:02 제출'), findsOneWidget);
  });

  testWidgets('한도 안내(note) 12 muted 줄높이 1.5 — 줄들 아래 8', (tester) async {
    const note = '이번 달 제출 3회를 모두 썼어요(승인 1건 · 검수 중 2건).';
    await pump(tester, [
      pending('a', at(14, 35), ['u1', 'u2']),
      pending('b', at(16, 2), ['u3']),
    ], note: note);

    final text = tester.widget<Text>(find.text(note)).style!;
    expect((text.fontSize, text.color, text.height), (12, AppColors.muted, 1.5));
    expect(tester.getTopLeft(find.text(note)).dy - tester.getBottomLeft(thumbs().last).dy, 8);
    expect(tester.getTopLeft(find.text(note)).dx - tester.getTopLeft(find.byType(HeartTaskPendingList)).dx, 40);
  });

  group('제출 시각 글자', () {
    final now = DateTime(2026, 10, 19, 18, 5);

    test('오늘이면 "오늘 HH:mm 제출"(24시간, 두 자리)', () {
      expect(heartTaskPendingTimeLabel(DateTime(2026, 10, 19, 9, 5), now), '오늘 09:05 제출');
      expect(heartTaskPendingTimeLabel(DateTime(2026, 10, 19, 14, 20), now), '오늘 14:20 제출');
    });

    test('오늘이 아니면 날짜를 붙인다(pen 에 없는 모양 — "M월 d일 HH:mm 제출")', () {
      expect(heartTaskPendingTimeLabel(DateTime(2026, 10, 18, 23, 59), now), '10월 18일 23:59 제출');
    });

    test('UTC 로 온 시각은 기기 시각으로 바꿔 읽는다', () {
      final utc = DateTime.utc(2026, 10, 19, 5, 20);
      final local = utc.toLocal();
      final expected = '오늘 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} 제출';
      expect(heartTaskPendingTimeLabel(utc, local), expected);
    });
  });

  testWidgets('낭독 — 줄마다 "시각, 사진 n장, 검수중" 한 덩어리로, 썸네일 그림은 읽지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, [
      pending('a', at(14, 20), ['u1', 'u2', 'u3']),
      pending('b', at(16, 2), ['u4', null]),
    ]);

    expect(find.bySemanticsLabel('오늘 14:20 제출, 사진 3장, 검수중'), findsOneWidget);
    expect(find.bySemanticsLabel('오늘 16:02 제출, 사진 2장, 검수중'), findsOneWidget);
    expect(find.bySemanticsLabel('검수 대기 2건'), findsOneWidget);
    handle.dispose();
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale — 넘침 · 말줄임 없고 썸네일은 36 그대로, 시각 글자가 접혀도 줄이 자란다', (tester) async {
      await pump(
        tester,
        [
          pending('a', at(14, 35), ['u1', 'u2', 'u3']),
          pending('b', at(16, 2), ['u4']),
        ],
        note: '이번 달 제출 3회를 모두 썼어요(승인 1건 · 검수 중 2건).',
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      for (final paragraph in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
        expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
      }
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(thumbs().at(i)), const Size(36, 36));
      }
      expect(tester.getRect(find.byType(HeartTaskPendingList)).width, 328);
    });
  }

  testWidgets('좁은 화면(폭 288, 글자 2배)에서도 썸네일 3장 + 배지가 넘치지 않는다', (tester) async {
    await pump(
      tester,
      [
        pending('a', at(14, 35), ['u1', 'u2', 'u3']),
      ],
      textScale: 2,
      width: 288,
    );

    expect(tester.takeException(), isNull);
  });
}
