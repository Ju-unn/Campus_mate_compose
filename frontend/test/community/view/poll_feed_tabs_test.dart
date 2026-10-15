import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/view/poll_feed_tabs.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/tour/view/app_tour_steps.dart';
import 'package:campus_mate/tour/view/tour_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final picked = <PollFeedTab>[];

  setUp(picked.clear);

  /// pen 화면 폭 360 — 탭 줄은 앱바 아래 PreferredSize 자리에 들어간다(화면과 같은 꽂음).
  Future<void> pump(WidgetTester tester, {PollFeedTab selected = PollFeedTab.all, double width = 360}) async {
    tester.view.physicalSize = Size(width, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(PollFeedTabs.heightFor(MediaQuery.textScalerOf(context))),
                child: PollFeedTabs(selected: selected, onSelected: picked.add),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(PollFeedTab tab) => find.byKey(PollFeedTabs.tabKey(tab));
  Finder ring(PollFeedTab tab) => find.byKey(PollFeedTabs.ringKey(tab));
  BoxDecoration ringDecoration(WidgetTester tester, PollFeedTab tab) =>
      tester.widget<Container>(ring(tab)).decoration! as BoxDecoration;

  testWidgets('pen 탭 줄(VEZ2l): 앱바 아래 폭 꽉 · 높이 102 · 안쪽 [4,16,12,16] · 탭 4개 72×86 양끝 맞춤', (tester) async {
    await pump(tester);

    final strip = tester.getRect(find.byType(PollFeedTabs));
    expect(strip, const Rect.fromLTWH(0, 56, 360, 102));
    final rects = [for (final value in PollFeedTab.values) tester.getRect(tab(value))];
    for (final value in PollFeedTab.values) {
      expect(tester.getSize(tab(value)), const Size(72, 86), reason: value.name);
      expect(tester.getRect(tab(value)).top, 56 + 4);
    }
    expect(rects.first.left, 16);
    expect(rects.last.right, 360 - 16);
    // space_between: 남는 폭 328 − 72 × 4 = 40 을 세 틈에 똑같이 나눈다.
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left - rects[i - 1].right, closeTo(40 / 3, 0.01));
    }
  });

  testWidgets('순서와 그림: 전체(투표 x5QLa) · 인기(반짝임 ulHL7) · 내 질문(프로필 PkqpC) · 내 투표(인증 Trtii)', (tester) async {
    await pump(tester);

    const expected = {
      PollFeedTab.all: ('전체', AppIcon3d.vote),
      PollFeedTab.popular: ('인기', AppIcon3d.sparkles),
      PollFeedTab.mine: ('내 질문', AppIcon3d.userRound),
      PollFeedTab.voted: ('내 투표', AppIcon3d.badgeCheck),
    };
    expect(PollFeedTab.values, [PollFeedTab.all, PollFeedTab.popular, PollFeedTab.mine, PollFeedTab.voted]);
    for (final MapEntry(key: value, value: (label, icon)) in expected.entries) {
      expect(find.descendant(of: tab(value), matching: find.text(label)), findsOneWidget, reason: label);
      final glyph = tester.widget<Icon3d>(find.descendant(of: tab(value), matching: find.byType(Icon3d)));
      expect((glyph.icon, glyph.size), (icon, 28), reason: label);
    }
  });

  testWidgets('탭(XfcKQ): 고리 64 · 테두리 2 · 흰 바탕 → 원판 54 primary-wash → 그림 28 가운데, 고리 아래 6 에 글자 12', (tester) async {
    await pump(tester);

    final tabRect = tester.getRect(tab(PollFeedTab.all));
    final ringRect = tester.getRect(ring(PollFeedTab.all));
    expect(ringRect.size, const Size(64, 64));
    expect((ringRect.top, ringRect.center.dx), (tabRect.top, tabRect.center.dx));
    final decoration = ringDecoration(tester, PollFeedTab.all);
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppColors.canvas);
    expect((decoration.border! as Border).top.width, 2);

    final disk = find.descendant(of: ring(PollFeedTab.all), matching: find.byType(DecoratedBox)).last;
    expect(tester.getRect(disk), Rect.fromCenter(center: ringRect.center, width: 54, height: 54));
    final diskDecoration = tester.widget<DecoratedBox>(disk).decoration as BoxDecoration;
    expect((diskDecoration.shape, diskDecoration.color), (BoxShape.circle, AppColors.primaryWash));
    final icon = find.descendant(of: tab(PollFeedTab.all), matching: find.byType(Icon3d));
    expect(tester.getCenter(icon), ringRect.center);

    final label = find.descendant(of: tab(PollFeedTab.all), matching: find.text('전체'));
    expect(tester.getRect(label).top - ringRect.bottom, 6);
    expect(tester.widget<Text>(label).style!.fontSize, 12);
    expect(tester.getRect(label).bottom, tabRect.bottom);
  });

  testWidgets('선택 = 고리 primary-rausch 2 + 글자 primary-text 700, 나머지 = hairline 2 + body 600', (tester) async {
    await pump(tester, selected: PollFeedTab.mine);

    for (final value in PollFeedTab.values) {
      final selected = value == PollFeedTab.mine;
      final side = (ringDecoration(tester, value).border! as Border).top;
      expect((side.color, side.width), (selected ? AppColors.primary : AppColors.hairline, 2), reason: value.name);
      final style = tester.widget<Text>(find.descendant(of: tab(value), matching: find.byType(Text))).style!;
      expect(
        (style.color, style.fontWeight),
        selected ? (AppColors.primaryText, FontWeight.w700) : (AppColors.body, FontWeight.w600),
        reason: value.name,
      );
    }
  });

  testWidgets('탭 72×86 어디를 눌러도 그 탭을 알린다(48 이상)', (tester) async {
    await pump(tester);

    final rect = tester.getRect(tab(PollFeedTab.voted));
    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    await tester.tapAt(rect.bottomRight - const Offset(1, 1));

    expect(picked, [PollFeedTab.voted, PollFeedTab.voted]);
  });

  testWidgets('낭독기는 탭마다 이름 · 선택 여부가 있는 버튼으로 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, selected: PollFeedTab.popular);

    expect(
      tester.getSemantics(tab(PollFeedTab.popular)),
      matchesSemantics(label: '인기', isButton: true, isSelected: true, hasSelectedState: true, hasTapAction: true, isFocusable: true, hasFocusAction: true),
    );
    expect(
      tester.getSemantics(tab(PollFeedTab.all)),
      matchesSemantics(label: '전체', isButton: true, hasSelectedState: true, hasTapAction: true, isFocusable: true, hasFocusAction: true),
    );
    semantics.dispose();
  });

  testWidgets('눌림 효과는 앱바가 아니라 그 탭 칸에 그려진다(COMMON §4-2 — 탭 줄이 가로로 밀린다)', (tester) async {
    await pump(tester);
    final ink = tab(PollFeedTab.mine);
    expect(tester.widget(ink), isA<InkWell>());
    final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(tab(PollFeedTab.mine)));
  });

  testWidgets('폰 폭(360) · 글자 2배: 넘치거나 잘리지 않고, 탭 줄이 가로로 밀려 마지막 탭까지 보인다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    expect(tester.takeException(), isNull);

    List<String> clipped() => [
          for (final element in find.descendant(of: find.byType(PollFeedTabs), matching: find.byType(RichText)).evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                    p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
              p.text.toPlainText(),
        ];
    expect(clipped(), isEmpty);
    // 글자가 고리보다 넓어지면 탭이 넓어지고, 탭끼리 붙지 않게 최소 틈을 둔다.
    final mine = tester.getRect(tab(PollFeedTab.mine));
    final voted = tester.getRect(tab(PollFeedTab.voted));
    expect(voted.left - mine.right, greaterThanOrEqualTo(8));

    final scrollable = find.descendant(of: find.byType(PollFeedTabs), matching: find.byType(Scrollable));
    expect(tester.widget<Scrollable>(scrollable).axisDirection, AxisDirection.right);
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, greaterThan(0));
    expect(tester.getRect(tab(PollFeedTab.voted)).right, greaterThan(360));

    await tester.drag(scrollable, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(tab(PollFeedTab.voted)).right, 360 - 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1배 · 넓은 화면에서는 밀리지 않는다 — 남는 폭은 탭 사이에 나눈다', (tester) async {
    await pump(tester, width: 411);
    final scrollable = find.descendant(of: find.byType(PollFeedTabs), matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, 0);
    expect(tester.getRect(tab(PollFeedTab.voted)).right, 411 - 16);
  });

  testWidgets('앱 투어 3단계 표식은 탭 4개 줄(안쪽 여백 밖, 첫 탭 왼쪽 ~ 끝 탭 오른쪽)에 붙는다', (tester) async {
    await pump(tester);

    final target = find.byWidgetPredicate((w) => w is TourTarget && w.id == TourTargetId.communityTabs);
    expect(target, findsOneWidget);
    final row = tester.getRect(target);
    expect(row.left, tester.getRect(tab(PollFeedTab.all)).left);
    expect(row.right, tester.getRect(tab(PollFeedTab.voted)).right);
    expect(row.top, tester.getRect(tab(PollFeedTab.all)).top);
    expect(row.bottom, tester.getRect(tab(PollFeedTab.all)).bottom);
  });
}
