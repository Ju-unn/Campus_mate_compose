import 'package:campus_mate/common/widgets/section_header.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [child])),
        ),
      ),
    );
  }

  group('SettingsSectionHeader(설정 · 알림 설정 · 계정) — 14/700 muted 글자 하나', () {
    testWidgets('14/700 muted, 줄높이 20, 왼쪽 정렬 · 아래 간격은 주지 않는다', (tester) async {
      await pump(tester, const SettingsSectionHeader('알림'));

      final text = tester.widget<Text>(find.text('알림'));
      expect((text.style!.fontSize, text.style!.fontWeight, text.style!.color), (14, FontWeight.w700, AppColors.muted));
      expect(tester.getSize(find.text('알림')).height, 20);
      expect(tester.getTopLeft(find.text('알림')).dx, 16);
      expect(tester.getSize(find.byType(SettingsSectionHeader)).height, 20);
    });
  });

  group('SectionHeader(pen Ymhdq) — 왼쪽 18/700 ink · 오른쪽 14/400 muted', () {
    testWidgets('제목만이면 18/700 ink 렌더 25, 오른쪽 글자는 그리지 않는다(Text 하나)', (tester) async {
      await pump(tester, const SectionHeader(title: '댓글 3'));

      final text = tester.widget<Text>(find.text('댓글 3'));
      expect((text.style!.fontSize, text.style!.fontWeight, text.style!.color), (18, FontWeight.w700, AppColors.ink));
      expect(tester.getSize(find.text('댓글 3')).height, 25);
      expect(find.descendant(of: find.byType(SectionHeader), matching: find.byType(Text)), findsOneWidget);
      expect(tester.getTopLeft(find.text('댓글 3')).dx, 16);
    });

    testWidgets('오른쪽 글자는 14/400 muted 렌더 20, 오른쪽 끝에 붙고 세로 가운데', (tester) async {
      await pump(tester, const SectionHeader(title: '선호 조건', trailing: '3개 선택'));

      final note = tester.widget<Text>(find.text('3개 선택'));
      expect((note.style!.fontSize, note.style!.fontWeight, note.style!.color), (14, FontWeight.w400, AppColors.muted));
      expect(tester.getSize(find.text('3개 선택')).height, 20);
      expect(tester.getTopRight(find.text('3개 선택')).dx, 344);
      expect(tester.getCenter(find.text('3개 선택')).dy, tester.getCenter(find.text('선호 조건')).dy);
    });

    testWidgets('오른쪽 글자가 길면 제목을 밀지 않고 오른쪽이 줄을 바꾼다(넘치지 않음)', (tester) async {
      await pump(tester, SectionHeader(title: '선호 조건', trailing: '아주 길어서 한 줄에 다 들어가지 않는 오른쪽 안내 글자입니다' * 2));

      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('선호 조건')).dx, 16);
    });

    testWidgets('key 를 그대로 받는다(대화 탭이 보낸 신청 머리 키로 스크롤한다)', (tester) async {
      await pump(tester, const SectionHeader(key: ValueKey('header'), title: '대화 중', trailing: '2명'));

      expect(find.byKey(const ValueKey('header')), findsOneWidget);
    });
  });
}
