import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_faq.dart';

void main() {
  late List<Uri> opened;
  late Future<bool> Function(Uri) openUrl;

  setUp(() {
    opened = [];
    openUrl = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  Future<void> pump(WidgetTester tester, {double textScale = 1.0, Future<void>? gate}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          faqRepositoryProvider.overrideWithValue(FakeFaqRepository(const Success(faqFixture), gate: gate)),
          faqCacheProvider.overrideWithValue(FakeFaqCache()),
          openUrlProvider.overrideWithValue((uri) => openUrl(uri)),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const FaqScreen(),
        ),
      ),
    );
    if (gate == null) await tester.pumpAndSettle();
  }

  TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

  testWidgets('앱바: 뒤로 화살표 22 는 가운데 (32,28), 제목 "자주 묻는 질문" 은 x60(pen OX1DW · xCEi8 · uEGfo)', (tester) async {
    await pump(tester);

    // pen: 버튼 48×48 이 (8,4), 화살표 22 가 그 안 (13,13) → 가운데 (32,28). 누름 칸은 앱바 높이만큼 세로로 늘어난다(폭 48).
    final arrow = find.byIcon(AppIcons.arrowLeft);
    expect(tester.getCenter(arrow), const Offset(32, 28));
    expect(tester.getSize(arrow), const Size(22, 22));
    final back = find.ancestor(of: arrow, matching: find.byType(IconButton));
    expect(tester.getSize(back).width, 48);
    expect(tester.getTopLeft(find.text('자주 묻는 질문')).dx, 60);
  });

  testWidgets('받는 중에는 가운데 스피너', (tester) async {
    final gate = Completer<void>();
    await pump(tester, gate: gate.future);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('검색칸: 공용 SearchField 48 상자가 (16,72), #F7F7F7 · 모서리 12 · 테두리 없음, 3D 돋보기 24 는 (32,84), 안내 글자 14 x64(pen y7Qlw, 대장 10-03)', (tester) async {
    await pump(tester);

    final field = find.byType(TextField);
    expect(tester.getTopLeft(field), const Offset(16, 72));
    expect(tester.getSize(field).height, 48);
    final decoration = tester.widget<TextField>(field).decoration!;
    expect(decoration.fillColor, AppColors.surfaceSoft);
    for (final border in [decoration.enabledBorder!, decoration.focusedBorder!]) {
      expect((border as OutlineInputBorder).borderSide, BorderSide.none);
      expect(border.borderRadius, BorderRadius.circular(AppRadius.input));
    }

    // 좌우 16 · 간격 8: 아이콘 (32,84)~(56,108), 가운데 (44,96) → 안내 글자 x 16 + 16 + 24 + 8.
    final icon = find.byType(Icon3d);
    expect(tester.widget<Icon3d>(icon).icon, AppIcon3d.search);
    expect(tester.getSize(icon), const Size(24, 24));
    expect(tester.getCenter(icon), const Offset(44, 96));
    expect(tester.getTopLeft(find.text('궁금한 내용을 검색해 보세요')).dx, 64);
    expect(decoration.hintStyle!.color, AppColors.muted);
    expect(decoration.hintStyle!.fontSize, 14);
  });

  testWidgets('탭 줄: 여섯 묶음이 enum 순서, 보이는 줄 136~174 · 누름 칸 48, 활성은 14/700 #C4224B + 밑줄(pen Sg89A · H2Qyx)', (tester) async {
    await pump(tester);

    final labels = ['카드·매칭', '하트·결제', '사진·프로필', '지인 리뷰', '안전·신고', '계정'];
    final lefts = [for (final l in labels) tester.getTopLeft(find.text(l)).dx];
    expect(lefts, orderedEquals([...lefts]..sort()));

    // 라벨은 보이는 줄 위(136)에서 10 아래. 누름 칸은 위로 10 더 올라가 48 이다(대장 09-29).
    expect(tester.getTopLeft(find.text('카드·매칭')).dy, 146);
    final tab = find.ancestor(of: find.text('계정'), matching: find.byType(InkWell));
    expect(tester.getRect(tab).top, 126);
    expect(tester.getSize(tab).height, 48);
    expect(tester.getSize(tab).width, greaterThanOrEqualTo(48));

    expect(styleOf(tester, '카드·매칭').fontWeight, FontWeight.w700);
    expect(styleOf(tester, '카드·매칭').color, AppColors.primaryText);
    expect(styleOf(tester, '하트·결제').fontWeight, FontWeight.w500);
    expect(styleOf(tester, '하트·결제').color, AppColors.muted);

    // 밑줄 2 는 탭 폭 그대로 보이는 줄 맨 아래(172~174). 비활성은 투명 밑줄이라 라벨 높이가 같다.
    Border underline(String label) {
      final tab = find.ancestor(of: find.text(label), matching: find.byType(InkWell));
      final box = tester.widget<Container>(find.descendant(of: tab, matching: find.byType(Container)).first);
      return (box.decoration! as BoxDecoration).border! as Border;
    }

    expect(underline('카드·매칭').bottom, const BorderSide(color: AppColors.primaryText, width: 2));
    expect(underline('하트·결제').bottom, const BorderSide(color: Colors.transparent, width: 2));
    expect(tester.getRect(tab).bottom, 174);
  });

  testWidgets('탭 화면은 고른 묶음 문항만 sort_order 순, 머리글 없이 본문 (16,190)부터(pen BqbHF · sI8Dm 꺼짐)', (tester) async {
    await pump(tester);

    expect(tester.getTopLeft(find.text('카드는 언제 오나요?')), const Offset(16, 190 + 16));
    expect(
      tester.getTopLeft(find.text('카드는 언제 오나요?')).dy,
      lessThan(tester.getTopLeft(find.text('왜 한 번에 한 장만 오나요?')).dy),
    );
    expect(find.text('하트는 어디에 쓰나요?'), findsNothing);
    expect(find.text('카드·매칭'), findsOneWidget); // 탭 라벨뿐 — 머리글은 없다
  });

  testWidgets('질문 줄: 18/700 #222222, chevron-down 20 #6A6A6A 오른쪽 끝, 접힘 55, 아래 선 #EBEBEB(pen KrMaM)', (tester) async {
    await pump(tester);

    final question = find.text('카드는 언제 오나요?');
    expect(styleOf(tester, '카드는 언제 오나요?').fontSize, AppTypography.label.fontSize);
    expect(styleOf(tester, '카드는 언제 오나요?').fontWeight, FontWeight.w700);
    expect(styleOf(tester, '카드는 언제 오나요?').color, AppColors.ink);

    final row = find.ancestor(of: question, matching: find.byType(InkWell)).first;
    expect(tester.getSize(row).height, closeTo(55, 1));
    final chevron = find.descendant(of: row, matching: find.byIcon(AppIcons.chevronDown));
    expect(tester.getSize(chevron), const Size(20, 20));
    expect(tester.getTopRight(chevron).dx, tester.getTopRight(row).dx);
    expect(tester.widget<Icon>(chevron).color, AppColors.muted);

    final box = tester.widget<Container>(find.descendant(of: row, matching: find.byType(Container)).first);
    final border = (box.decoration! as BoxDecoration).border! as Border;
    expect(border.bottom, const BorderSide(color: AppColors.hairlineSoft));
  });

  testWidgets('누르면 답이 질문 아래 12 에 16/400 #6A6A6A 로 펼쳐지고 질문은 #C4224B · chevron-up, 다른 질문을 누르면 앞의 답은 접힌다(pen ElIjG)', (tester) async {
    await pump(tester);
    expect(find.text('지급일 아침 7시에 와요.'), findsNothing);

    await tester.tap(find.text('카드는 언제 오나요?'));
    await tester.pumpAndSettle();
    expect(find.text('지급일 아침 7시에 와요.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('지급일 아침 7시에 와요.')).dy,
      tester.getBottomLeft(find.text('카드는 언제 오나요?')).dy + 12,
    );
    expect(styleOf(tester, '지급일 아침 7시에 와요.').fontSize, 16);
    expect(styleOf(tester, '지급일 아침 7시에 와요.').color, AppColors.muted);
    expect(styleOf(tester, '카드는 언제 오나요?').color, AppColors.primaryText);
    expect(find.byIcon(AppIcons.chevronUp), findsOneWidget);

    await tester.tap(find.text('왜 한 번에 한 장만 오나요?'));
    await tester.pumpAndSettle();
    expect(find.text('지급일 아침 7시에 와요.'), findsNothing);
    expect(find.text('사진은 점수에 들어가지 않아요.'), findsOneWidget);
  });

  testWidgets('탭을 누르면 그 묶음 문항으로 바뀌고 펼친 답은 접힌다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('카드는 언제 오나요?'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('안전·신고'));
    await tester.pumpAndSettle();
    expect(find.text('신고하면 어떻게 되나요?'), findsOneWidget);
    expect(find.text('카드는 언제 오나요?'), findsNothing);
    expect(styleOf(tester, '안전·신고').color, AppColors.primaryText);

    await tester.tap(find.text('카드·매칭'));
    await tester.pumpAndSettle();
    expect(find.text('지급일 아침 7시에 와요.'), findsNothing);
  });

  testWidgets('검색 중에는 탭 줄 대신 전 묶음을 머리글(20/600)과 함께, 지우면 고른 탭으로 돌아간다(사용자 결정 ① 가)', (tester) async {
    await pump(tester);
    await tester.tap(find.text('안전·신고'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '신고');
    await tester.pumpAndSettle();
    // f1 은 답변("신고할 수 있어요.")에만 걸린다.
    expect(find.text('리뷰가 부적절하면 어떻게 하나요?'), findsOneWidget);
    expect(find.text('신고하면 어떻게 되나요?'), findsOneWidget);
    expect(find.text('카드·매칭'), findsNothing); // 탭 줄이 숨는다
    expect(styleOf(tester, '지인 리뷰').fontSize, AppTypography.title.fontSize);
    expect(styleOf(tester, '지인 리뷰').fontWeight, FontWeight.w600);
    // 머리글 → 문항 gap 8, 묶음 사이 gap 32(pen iyddt · BqbHF).
    final header = tester.getRect(find.text('지인 리뷰'));
    final firstRow = tester.getRect(find.ancestor(of: find.text('리뷰가 부적절하면 어떻게 하나요?'), matching: find.byType(InkWell)).first);
    expect(firstRow.top, header.bottom + 8);
    expect(tester.getTopLeft(find.text('안전·신고')).dy, firstRow.bottom + 32);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('카드·매칭'), findsOneWidget);
    expect(styleOf(tester, '안전·신고').color, AppColors.primaryText);
    expect(find.text('리뷰가 부적절하면 어떻게 하나요?'), findsNothing);
  });

  testWidgets('검색 중 본문은 탭 줄 없이 (16,136+16)부터 — 검색칸 아래 여백 16(pen 21-1 qi9ib · jH9Da)', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '신고');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('지인 리뷰')), const Offset(16, 136 + 16));
  });

  Future<void> searchNothing(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '없는말');
    await tester.pumpAndSettle();
  }

  const mail = 'appmailerl4538@gmail.com';

  testWidgets('걸린 게 없으면 21-1 빈 상태: 마스코트 120 → 24 → 제목 17/600 → 8 → 설명 세 줄, 메일만 14/600 #C4224B(pen IhXOF)', (tester) async {
    await pump(tester);
    await searchNothing(tester);

    final mascot = find.image(const AssetImage('assets/images/mascot-male.png'));
    expect(tester.getSize(mascot), const Size(120, 120));
    final title = find.text('찾는 질문이 없어요');
    expect(tester.getTopLeft(title).dy, tester.getBottomLeft(mascot).dy + 24);
    expect(styleOf(tester, '찾는 질문이 없어요').fontSize, 17);
    expect(styleOf(tester, '찾는 질문이 없어요').fontWeight, FontWeight.w600);
    expect(styleOf(tester, '찾는 질문이 없어요').color, AppColors.ink);

    final first = find.text('다른 말로 검색하거나');
    expect(tester.getTopLeft(first).dy, tester.getBottomLeft(title).dy + 8);
    for (final line in ['다른 말로 검색하거나', '으로', '물어봐 주세요']) {
      expect(styleOf(tester, line).fontSize, 14);
      expect(styleOf(tester, line).color, AppColors.muted);
    }
    final link = tester.renderObject<RenderParagraph>(find.text(mail)).text.style!;
    expect(link.fontSize, 14);
    expect(link.fontWeight, FontWeight.w600);
    expect(link.color, AppColors.primaryText);
    // 메일 · "으로" 는 한 줄, 사이 4(pen `CvTKu`).
    expect(tester.getCenter(find.text('으로')).dy, tester.getCenter(find.text(mail)).dy);
    expect(tester.getTopLeft(find.text('으로')).dx, tester.getTopRight(find.text(mail)).dx + 4);

    // 본문(136~600) 한가운데 — Empty `justifyContent center`.
    final top = tester.getTopLeft(mascot).dy;
    final bottom = tester.getBottomLeft(find.text('물어봐 주세요')).dy;
    expect((top + bottom) / 2, closeTo((136 + 600) / 2, 1));
  });

  testWidgets('메일 주소는 누름 48, 누르면 mailto 로 메일 앱을 연다(대장 09-29)', (tester) async {
    await pump(tester);
    await searchNothing(tester);

    final button = find.ancestor(of: find.text(mail), matching: find.byType(TextButton));
    expect(tester.getSize(button).height, 48);
    await tester.tap(find.text(mail));
    await tester.pump();
    expect(opened, [Uri.parse('mailto:$mail')]);
    expect(find.byType(AppToast), findsNothing);
  });

  testWidgets('메일 앱을 못 열면 안내를 3초 띄우고 화면에 남는다 — 가입 동의 화면과 같다(대장 09-29)', (tester) async {
    openUrl = (_) async => false;
    await pump(tester);
    await searchNothing(tester);

    await tester.tap(find.text(mail));
    await tester.pump();
    expect(find.widgetWithText(AppToast, const UnknownFailure().toDisplayMessage()), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(AppToast), findsNothing);

    openUrl = (_) async => throw Exception('no mail app');
    await tester.tap(find.text(mail));
    await tester.pump();
    expect(find.widgetWithText(AppToast, const UnknownFailure().toDisplayMessage()), findsOneWidget);
    expect(find.text('찾는 질문이 없어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('360 폭 · 2.0배에서 검색칸 안내 글자가 말줄임 없이 다 보인다(칸이 따라 커진다)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, textScale: 2.0);
    expect(tester.renderObject<RenderParagraph>(find.text('궁금한 내용을 검색해 보세요')).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360 폭 · 2.0배에서 빈 상태의 긴 메일 주소가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, textScale: 2.0);
    await tester.enterText(find.byType(TextField), '없는말');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('찾는 질문이 없어요'), findsOneWidget);
  });

  testWidgets('✕ 는 검색어가 있을 때만, lucide x 20 #6A6A6A 가운데 (318,96) · 누름 48, 누르면 검색어를 지우고 고른 탭 화면으로(pen nXpvH/uvQHG)', (tester) async {
    await pump(tester);
    expect(find.byIcon(AppIcons.x), findsNothing);
    await tester.tap(find.text('안전·신고'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '없는말');
    await tester.pumpAndSettle();
    final clear = find.byIcon(AppIcons.x);
    expect(tester.getCenter(clear), const Offset(800 - 16 - 16 - 10, 96));
    expect(tester.getSize(clear), const Size(20, 20));
    expect(tester.widget<Icon>(clear).color, AppColors.muted);
    expect(tester.getSize(find.ancestor(of: clear, matching: find.byType(IconButton))), const Size(48, 48));

    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.byIcon(AppIcons.x), findsNothing);
    expect(styleOf(tester, '안전·신고').color, AppColors.primaryText);
    expect(find.text('신고하면 어떻게 되나요?'), findsOneWidget);
  });

  testWidgets('검색 중에 뒤로 가기를 누르면 검색어를 지우지 않고 화면을 나간다(대장 09-29)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          faqRepositoryProvider.overrideWithValue(FakeFaqRepository(const Success(faqFixture))),
          faqCacheProvider.overrideWithValue(FakeFaqCache()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FaqScreen())),
              child: const Text('설정'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '신고');
    await tester.pumpAndSettle();

    // 안드로이드 시스템 뒤로. 앱바 화살표도 같은 maybePop 이다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FaqScreen), findsNothing);
    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('질문 줄의 잉크는 줄 크기의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await pump(tester);
    final question = find.text('카드는 언제 오나요?');
    final material = find.ancestor(of: question, matching: find.byType(Material)).first;
    final ink = find.ancestor(of: question, matching: find.byType(InkWell)).first;
    expect(tester.getSize(material), tester.getSize(ink));
  });

  testWidgets('2.0배에서 긴 질문과 펼친 답이 넘치지 않는다', (tester) async {
    await pump(tester, textScale: 2.0);
    // 탭 줄 · 검색칸에도 Scrollable 이 있어 본문 목록을 집어 준다.
    await tester.ensureVisible(find.text('계정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계정'));
    await tester.pumpAndSettle();
    const long = '누가 가입할 수 있나요? 재학생이 아니어도 되나요?';
    await tester.scrollUntilVisible(
      find.text(long),
      200,
      scrollable: find.descendant(of: find.byKey(const ValueKey('faq-list')), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('졸업 여부는 따로 확인하지 않아요.'), findsOneWidget);
  });
}
