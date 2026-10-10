import 'dart:io';
import 'dart:ui' as ui;

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/matching/view/paid_card_locked.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 결제 카드(잠금 카드) 마스터 `qoYnh` 328×368 과 0명 안내 `IJGRA` 를 pen 값(지시문 23 B · E, 값표 §1~3 · §7)과 대조한다.
/// 시험 기본 글꼴(Ahem)은 글자 폭이 전부 같아 태그 줄바꿈이 실제와 다르다 — Pretendard 를 불러서 잰다.
Future<void> _loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/Pretendard-$weight.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}

/// pen 예시 문구 그대로(값표 §2): 행1 두 개, 행2 한 개.
const _penReasons = [
  ReasonTag(kind: 'tendency', text: '성향이 비슷해요'),
  ReasonTag(kind: 'tags', text: '#러닝 #카페가 같아요'),
  ReasonTag(kind: 'ideal', text: "'이런 사람이 좋아요'와 잘 맞아요"),
];

PaidCardOffered _offer({
  int bandCount = 7,
  List<ReasonTag> reasons = _penReasons,
  String? avatarUrl,
  int cost = 50,
}) =>
    PaidCardOffered(offerId: 'offer-1', bandCount: bandCount, reasons: reasons, avatarUrl: avatarUrl, cost: cost);

bool _isReasonTag(Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('reason-tag:');

void main() {
  setUpAll(_loadPretendard);

  Future<void> pump(
    WidgetTester tester, {
    PaidCardOffered? offer,
    VoidCallback? onOpen,
    VoidCallback? onInfo,
    bool busy = false,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PaidCardLocked(
              card: offer ?? _offer(),
              onOpen: onOpen ?? () {},
              onInfo: onInfo ?? () {},
              busy: busy,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder card() => find.byType(PaidCardLocked);
  Rect rel(WidgetTester tester, Finder finder) {
    final origin = tester.getTopLeft(card());
    final r = tester.getRect(finder);
    return Rect.fromLTWH(r.left - origin.dx, r.top - origin.dy, r.width, r.height);
  }

  BoxDecoration decorationOf(WidgetTester tester, Finder finder) =>
      tester.widget<DecoratedBox>(finder).decoration as BoxDecoration;

  group('틀 `qoYnh`', () {
    testWidgets('328×368 — 아바타 20 · 14 · 문구 52 · 14 · 태그 62 · 14 · 버튼 52 · 14 · 안내 18 · 아래 20', (tester) async {
      await pump(tester);

      expect(tester.getSize(card()), const Size(328, 368));
    });

    testWidgets('채움 #F7F7F7 · 테두리 1 #EBEBEB · 모서리 24 · 그림자 2겹 = AppElevation.cardSoft', (tester) async {
      await pump(tester);

      final frame = decorationOf(tester, find.byKey(const ValueKey('paid-card-frame')));
      expect(frame.color, AppColors.surfaceSoft);
      expect(frame.color, const Color(0xFFF7F7F7));
      final border = frame.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, const Color(0xFFEBEBEB));
      expect(frame.borderRadius, BorderRadius.circular(24));
      // pen: (0,2) blur 8 #1A16190A / (0,8) blur 20 #1A16190F
      expect(frame.boxShadow, AppElevation.cardSoft);
    });
  });

  group('모자이크 아바타 `FLFiL`', () {
    testWidgets('88×88 원, 가로 가운데(x120)에 위 20', (tester) async {
      await pump(tester);

      expect(rel(tester, find.byKey(const ValueKey('paid-card-avatar'))), const Rect.fromLTWH(120, 20, 88, 88));
    });

    testWidgets('사진은 blur 10 을 입힌 채로만 그린다 — 흐리지 않은 원본이 어디에도 없다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, offer: _offer(avatarUrl: 'https://cdn.test/original.png'));

      final photos = find.byKey(const ValueKey('paid-card-photo'));
      expect(photos, findsOneWidget);
      final blurred = find.ancestor(of: photos, matching: find.byType(ImageFiltered));
      expect(blurred, findsOneWidget);
      expect(tester.widget<ImageFiltered>(blurred).imageFilter, ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10));
      // 사진에는 낭독 이름이 붙지 않는다.
      expect(find.bySemanticsLabel(RegExp('original|cdn')), findsNothing);
      semantics.dispose();
    });

    testWidgets('사진이 없으면 회색 원 + 자물쇠', (tester) async {
      await pump(tester, offer: _offer(avatarUrl: null));

      expect(find.byKey(const ValueKey('paid-card-photo')), findsNothing);
      final empty = tester.widget<DecoratedBox>(find.byKey(const ValueKey('paid-card-avatar-fallback')));
      expect((empty.decoration as BoxDecoration).color, AppColors.surfaceStrong);
      expect(find.byKey(const ValueKey('paid-card-lock')), findsOneWidget);
    });

    testWidgets('자물쇠 원 `DMOuj` 36×36 아바타 안 (26,26), 흰색 80%(#FFFFFFCC) · 안의 lock 18 #222222', (tester) async {
      await pump(tester);

      final lock = find.byKey(const ValueKey('paid-card-lock'));
      final avatar = rel(tester, find.byKey(const ValueKey('paid-card-avatar')));
      final circle = rel(tester, lock);
      expect(circle.size, const Size(36, 36));
      expect(circle.left - avatar.left, 26);
      expect(circle.top - avatar.top, 26);
      final decoration = decorationOf(tester, find.descendant(of: lock, matching: find.byType(DecoratedBox)).first);
      expect(decoration.color, const Color(0xCCFFFFFF));
      expect(decoration.shape, BoxShape.circle);
      final icon = tester.widget<Icon>(find.descendant(of: lock, matching: find.byType(Icon)));
      expect(icon.icon, AppIcons.lock);
      expect(icon.size, 18);
      expect(icon.color, const Color(0xFF222222));
    });
  });

  group('제목 `H7ko9`', () {
    testWidgets('"나와 성향이 잘 맞는 사람\\nN명이 기다리고 있어요" 17/600/1.45 #222222 가운데, y122 · 폭 288', (tester) async {
      await pump(tester);

      final headline = find.text('나와 성향이 잘 맞는 사람\n7명이 기다리고 있어요');
      expect(headline, findsOneWidget);
      final text = tester.widget<Text>(headline);
      expect(text.style!.fontSize, 17);
      expect(text.style!.fontWeight, FontWeight.w600);
      expect(text.style!.height, 1.45);
      expect(text.style!.color, const Color(0xFF222222));
      expect(text.textAlign, TextAlign.center);
      final box = rel(tester, find.byKey(const ValueKey('paid-card-headline')));
      expect(box.left, 20);
      expect(box.top, 122);
      expect(box.width, 288);
      expect(box.height, greaterThanOrEqualTo(52));
    });

    testWidgets('1명이어도 그대로 "1명이" 라고 쓴다', (tester) async {
      await pump(tester, offer: _offer(bandCount: 1));

      expect(find.text('나와 성향이 잘 맞는 사람\n1명이 기다리고 있어요'), findsOneWidget);
    });
  });

  group('이유 태그 `oAdfz`', () {
    Finder tag(String text) => find.byKey(ValueKey('reason-tag:$text'));

    testWidgets('y188 에서 시작, 행 높이 28, 세로 간격 6 — 행1 두 개 · 행2 한 개(pen 예시)', (tester) async {
      await pump(tester);

      final first = rel(tester, tag('성향이 비슷해요'));
      final second = rel(tester, tag('#러닝 #카페가 같아요'));
      final third = rel(tester, tag("'이런 사람이 좋아요'와 잘 맞아요"));
      expect(first.top, 188);
      expect(first.height, 28);
      expect(second.top, 188);
      expect(second.left - first.right, 6);
      expect(third.top, 188 + 28 + 6);
      expect(third.height, 28);
      // 가운데 정렬: 태그 줄 양쪽 여백이 같다.
      expect(first.left - 20, closeTo(328 - 20 - second.right, 0.5));
      expect(third.left + third.width / 2, closeTo(164, 0.5));
    });

    testWidgets('태그 모양 — 모서리 pill · 채움 #FFFFFF · 테두리 1 #EBEBEB · 가로 padding 11 · 글자 12/400 #3F3F3F', (tester) async {
      await pump(tester);

      final decoration = decorationOf(tester, tag('성향이 비슷해요'));
      expect(decoration.color, const Color(0xFFFFFFFF));
      expect((decoration.border! as Border).top.color, const Color(0xFFEBEBEB));
      expect((decoration.border! as Border).top.width, 1);
      expect(decoration.borderRadius, BorderRadius.circular(9999));
      final style = tester.widget<Text>(find.text('성향이 비슷해요')).style!;
      expect(style.fontSize, 12);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, const Color(0xFF3F3F3F));
      final box = rel(tester, tag('성향이 비슷해요'));
      final label = rel(tester, find.text('성향이 비슷해요'));
      expect(label.left - box.left, 11);
      expect(box.right - label.right, 11);
    });

    testWidgets('4개가 와도 3개까지만 그린다', (tester) async {
      await pump(
        tester,
        offer: _offer(reasons: [..._penReasons, const ReasonTag(kind: 'mbti', text: 'MBTI가 잘 맞아요')]),
      );

      expect(find.text('MBTI가 잘 맞아요'), findsNothing);
      expect(find.byWidgetPredicate(_isReasonTag), findsNWidgets(3));
    });

    testWidgets('이유가 하나도 없으면 태그 자리를 접는다 — 빈 줄이 남지 않는다', (tester) async {
      await pump(tester, offer: _offer(reasons: const []));

      expect(find.byWidgetPredicate(_isReasonTag), findsNothing);
      expect(tester.getSize(card()).height, 368 - 62 - 14);
    });
  });

  group('버튼 `M7dH2I`', () {
    testWidgets('288×52 y264, 모서리 8, #FF385C, 하트 26×26 + 간격 8 + "50으로 열기" 18/700 #FFFFFF', (tester) async {
      await pump(tester);

      final button = find.byKey(const ValueKey('paid-card-open'));
      expect(rel(tester, button), const Rect.fromLTWH(20, 264, 288, 52));
      final material = tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first);
      expect(material.color, const Color(0xFFFF385C));
      expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
      final label = find.text('50으로 열기');
      final style = tester.widget<Text>(label).style!;
      expect(style.fontSize, 18);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, const Color(0xFFFFFFFF));
      final heart = find.descendant(of: button, matching: find.byType(Image));
      expect(tester.getSize(heart), const Size(26, 26));
      expect((tester.widget<Image>(heart).image as AssetImage).assetName, 'assets/images/heart-flat-vector-on-primary-v1.png');
      expect(tester.getRect(label).left - tester.getRect(heart).right, 8);
    });

    testWidgets('숫자는 서버가 준 cost 를 쓴다', (tester) async {
      await pump(tester, offer: _offer(cost: 70));

      expect(find.text('70으로 열기'), findsOneWidget);
      expect(find.text('50으로 열기'), findsNothing);
    });

    testWidgets('누르면 onOpen 이 불린다. 여는 중(busy)에는 눌러도 안 불린다', (tester) async {
      var opened = 0;
      await pump(tester, onOpen: () => opened++);
      await tester.tap(find.text('50으로 열기'));
      expect(opened, 1);

      await pump(tester, onOpen: () => opened++, busy: true);
      await tester.tap(find.text('50으로 열기'));
      expect(opened, 1);
    });
  });

  group('안내 `SGkJM`', () {
    testWidgets('"다음 카드가 오기 전까지 한 명만 열 수 있어요" 12/400/1.4 #6A6A6A 가운데, y330 · 폭 288 · 높이 18', (tester) async {
      await pump(tester);

      final caption = find.text('다음 카드가 오기 전까지 한 명만 열 수 있어요');
      final style = tester.widget<Text>(caption).style!;
      expect(style.fontSize, 12);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.height, 1.4);
      expect(style.color, const Color(0xFF6A6A6A));
      expect(tester.widget<Text>(caption).textAlign, TextAlign.center);
      final box = rel(tester, find.byKey(const ValueKey('paid-card-caption')));
      expect(box, const Rect.fromLTWH(20, 330, 288, 18));
    });
  });

  group('물음표 `MHRC6`', () {
    testWidgets('보이는 그림 22×22 가 (290,16), 눌림 칸은 48×48 로 그 가운데, 읽기 이름 "맞는 이유 안내"', (tester) async {
      final semantics = tester.ensureSemantics();
      var tapped = 0;
      await pump(tester, onInfo: () => tapped++);

      final icon = find.descendant(
        of: card(),
        matching: find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.help),
      );
      expect(rel(tester, icon), const Rect.fromLTWH(290, 16, 22, 22));
      final target = find.byKey(const ValueKey('paid-card-info'));
      final area = rel(tester, target);
      expect(area.width, greaterThanOrEqualTo(48));
      expect(area.height, greaterThanOrEqualTo(48));
      expect(area.center.dx, closeTo(301, 0.5));
      expect(area.center.dy, closeTo(27, 0.5));
      expect(find.bySemanticsLabel('맞는 이유 안내'), findsOneWidget);

      // 보이는 그림 바깥(눌림 칸 안쪽 가장자리)을 눌러도 열린다.
      await tester.tapAt(tester.getTopLeft(target) + const Offset(3, 3));
      expect(tapped, 1);
      semantics.dispose();
    });

    testWidgets('눌림 효과는 화면이 아니라 이 칸이 칠한다(COMMON §4-2)', (tester) async {
      await pump(tester);

      final inkWell = find.descendant(of: find.byKey(const ValueKey('paid-card-info')), matching: find.byType(InkWell));
      expect(inkWell, findsOneWidget);
      final material = find.ancestor(of: inkWell, matching: find.byType(Material)).first;
      expect(tester.getSize(material).width, lessThan(100));
    });
  });

  group('금지 문구(지시문 23 — 점수 · 순위 숫자 · 비중 · 학교 이름을 화면에 두지 않는다)', () {
    testWidgets('% · "상위" · "궁합" · "점수" · 학교 · "이상형 조건에 맞는" 이 카드 안에 없다', (tester) async {
      await pump(tester);

      final all = [
        for (final t in tester.widgetList<Text>(find.descendant(of: card(), matching: find.byType(Text)))) t.data ?? '',
      ].join('|');
      for (final banned in ['%', '상위', '궁합', '점수', '대학교', '이상형 조건에 맞는']) {
        expect(all.contains(banned), isFalse, reason: banned);
      }
    });
  });

  group('0명 안내 `IJGRA`', () {
    testWidgets('328×48, #F7F7F7, 모서리 12, padding (14,16), lock 14 #3F3F3F + 14/600 #222222 글자, 누를 수 없다', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: PaidCardEmptyNotice())),
        ),
      );

      final notice = find.byType(PaidCardEmptyNotice);
      expect(tester.getSize(notice), const Size(328, 48));
      final box = tester.widget<DecoratedBox>(find.descendant(of: notice, matching: find.byType(DecoratedBox)).first).decoration
          as BoxDecoration;
      expect(box.color, const Color(0xFFF7F7F7));
      expect(box.borderRadius, BorderRadius.circular(12));
      final icon = tester.widget<Icon>(find.descendant(of: notice, matching: find.byType(Icon)));
      expect(icon.icon, AppIcons.lock);
      expect(icon.size, 14);
      expect(icon.color, const Color(0xFF3F3F3F));
      final style = tester.widget<Text>(find.text('잘 맞는 새 사람이 들어오면 다시 열려요')).style!;
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, const Color(0xFF222222));
      expect(tester.getTopLeft(find.byType(Icon)).dx - tester.getTopLeft(notice).dx, 16);
      expect(find.descendant(of: notice, matching: find.byType(InkWell)), findsNothing);
      expect(find.descendant(of: notice, matching: find.byType(GestureDetector)), findsNothing);
    });
  });

  testWidgets('글자를 키워도(2.0) 넘치거나 잘리지 않는다 — 카드가 따라 커진다', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(card()).height, greaterThan(368));
  });
}
