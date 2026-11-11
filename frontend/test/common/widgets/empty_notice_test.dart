import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageKey = ValueKey('image');
  const image = ColoredBox(key: imageKey, color: Colors.grey);

  /// 360×780 화면, 가운데 배치용 본문 칸은 (0,0)~(360,600)이다.
  Future<void> pump(WidgetTester tester, Widget notice, {double textScale = 1}) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: Column(children: [SizedBox(height: 600, child: notice)])),
      ),
    );
  }

  group('가운데 배치(pen Empty TVc8b)', () {
    testWidgets('그림 120×120 → 24 → 제목 18/600 ink 렌더 25 → 8 → 설명 14 muted 1.55, 모두 가운데', (tester) async {
      await pump(tester, const EmptyNotice(image: image, title: '비었어요', description: '여기엔 아직 없어요'));

      expect(tester.getSize(find.byKey(imageKey)), const Size(120, 120));
      final title = tester.widget<Text>(find.text('비었어요'));
      expect((title.style!.fontSize, title.style!.fontWeight, title.style!.color), (18, FontWeight.w600, AppColors.ink));
      expect(title.textAlign, TextAlign.center);
      expect(tester.getSize(find.text('비었어요')).height, 25);
      final description = tester.widget<Text>(find.text('여기엔 아직 없어요'));
      expect((description.style!.fontSize, description.style!.color, description.style!.height), (14, AppColors.muted, 1.55));
      expect(description.textAlign, TextAlign.center);

      final imageRect = tester.getRect(find.byKey(imageKey));
      final titleRect = tester.getRect(find.text('비었어요'));
      final descriptionRect = tester.getRect(find.text('여기엔 아직 없어요'));
      expect(titleRect.top - imageRect.bottom, 24);
      expect(descriptionRect.top - titleRect.bottom, 8);
      expect(imageRect.center.dx, 180);
      expect(titleRect.center.dx, 180);
      // 본문 칸(높이 600)의 세로 가운데 — 안쪽 여백 48 은 위아래가 같아 가운데를 옮기지 않는다.
      final content = imageRect.top - 48;
      expect(content + (descriptionRect.bottom + 48 - content) / 2, 300);
    });

    testWidgets('설명이 없으면 제목까지만 그린다(간격 8 도 없다)', (tester) async {
      await pump(tester, const EmptyNotice(image: image, title: '제목만'));

      expect(find.byType(Text), findsOneWidget);
      // 내용 높이 = 48 + 120 + 24 + 25 + 48 = 265 — 본문 칸(600)의 가운데.
      expect(tester.getRect(find.byKey(imageKey)).top, closeTo((600 - 265) / 2 + 48, 0.5));
    });

    testWidgets('버튼 자리는 설명 아래 32, 간격은 인자로 바꾼다', (tester) async {
      await pump(
        tester,
        const EmptyNotice(image: image, title: '제목', description: '설명', action: SizedBox(key: ValueKey('action'), height: 52)),
      );
      expect(tester.getRect(find.byKey(const ValueKey('action'))).top - tester.getRect(find.text('설명')).bottom, 32);

      await pump(
        tester,
        const EmptyNotice(
          image: image,
          title: '제목',
          description: '설명',
          actionGap: 16,
          action: SizedBox(key: ValueKey('action'), height: 52),
        ),
      );
      expect(tester.getRect(find.byKey(const ValueKey('action'))).top - tester.getRect(find.text('설명')).bottom, 16);
    });

    testWidgets('설명 자리에 위젯을 받는다(검색 0개 — 세 줄과 링크)', (tester) async {
      await pump(
        tester,
        const EmptyNotice(image: image, title: '제목', descriptionWidget: SizedBox(key: ValueKey('rich'), height: 60)),
      );

      expect(tester.getRect(find.byKey(const ValueKey('rich'))).top - tester.getRect(find.text('제목')).bottom, 8);
    });

    testWidgets('안쪽 여백은 인자로 바꾼다 — 가로를 줄이면 글자 폭이 넓어진다', (tester) async {
      const long = '아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주아주';
      await pump(tester, const EmptyNotice(image: image, title: '제목', description: long));
      final narrow = tester.getSize(find.text(long)).width;
      expect(narrow, lessThanOrEqualTo(360 - 48));

      await pump(
        tester,
        const EmptyNotice(image: image, title: '제목', description: long, padding: EdgeInsets.symmetric(vertical: 48)),
      );
      expect(tester.getSize(find.text(long)).width, greaterThan(narrow));
    });

    testWidgets('바깥 스크롤 여백을 주면 그 안쪽 칸의 가운데에 놓인다(차단 목록의 목록 여백)', (tester) async {
      await pump(
        tester,
        const EmptyNotice(
          image: image,
          title: '제목',
          scrollPadding: EdgeInsets.fromLTRB(16, 12, 16, 24),
        ),
      );

      final box = tester.getRect(find.byKey(imageKey));
      // 내용 높이 = 48 + 120 + 24 + 25 + 48 = 265, 칸은 y12 ~ 576(높이 564).
      expect(box.top - 48, closeTo(12 + (564 - 265) / 2, 0.5));
    });

    testWidgets('글자를 2배로 키워 칸을 넘치면 넘침 오류 없이 스크롤한다', (tester) async {
      await pump(
        tester,
        const EmptyNotice(image: image, title: '제목이 조금 길어요 제목이 조금 길어요', description: '설명도 길어요 설명도 길어요 설명도 길어요 설명도 길어요 설명도 길어요 설명도 길어요'),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('높이가 정해지지 않은 자리(스크롤 안)에서도 터지지 않고 내용만큼 선다', (tester) async {
      await pump(
        tester,
        const SingleChildScrollView(child: EmptyNotice(image: image, title: '제목', description: '설명')),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(imageKey)).top, 48);
    });

    testWidgets('제목 글꼴을 인자로 바꾼다(큰 안내 화면 3곳이 largeTitleStyle 을 넘긴다)', (tester) async {
      await pump(
        tester,
        EmptyNotice(image: image, title: '제목', description: '설명', titleStyle: EmptyNotice.largeTitleStyle),
      );

      expect(tester.widget<Text>(find.text('제목')).style, EmptyNotice.largeTitleStyle);
      expect(tester.getSize(find.text('제목')).height, 30);
    });
  });

  group('위에서 시작(알림 · 큰 안내 화면)', () {
    testWidgets('가운데로 옮기지 않고 안쪽 여백 48 아래에서 시작, 가로로 꽉 찬다', (tester) async {
      await pump(tester, const SingleChildScrollView(child: EmptyNotice(image: image, title: '제목', description: '설명', align: EmptyNoticeAlign.top, key: ValueKey('notice'))));

      expect(tester.getRect(find.byKey(imageKey)).top, 48);
      final notice = tester.getRect(find.byKey(const ValueKey('notice')));
      expect(notice.width, 360);
      expect(notice.top, 0);
      expect(tester.getRect(find.text('제목')).top - tester.getRect(find.byKey(imageKey)).bottom, 24);
    });
  });
}
