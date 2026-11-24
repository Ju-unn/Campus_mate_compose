import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/view/rejected_card_row.dart';
import 'package:campus_mate/matching/view/sent_request_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 거절한 카드 줄(pen `pdOvf` RejectedCardRow — UI값표 CT5Lq 0-1 · 20-2): SentRequestRow(d6otzp) 모양 줄 → 12 → 버튼 띠(gap 8)
/// [프로필 보기](보조 surface-strong · ink) + [다시 신청하기](primary), 받은 신청 출처면 [수락하기]. 버튼은 AppButton 작은 크기(대장 판정 6).
RejectedCard _card({RejectedSource source = RejectedSource.card, int daysLeft = 5}) => RejectedCard(
      cardId: 'card-1',
      source: source,
      daysLeft: daysLeft,
      profile: const CardProfile(nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
    );

void main() {
  var profileTaps = 0;
  var actionTaps = 0;

  setUp(() {
    profileTaps = 0;
    actionTaps = 0;
  });

  Future<void> pump(WidgetTester tester, RejectedCard card, {bool enabled = true, bool submitting = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [universityLogosProvider.overrideWith((ref) => const <String, String>{})],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 328,
                child: RejectedCardRow(
                  card: card,
                  isSubmitting: submitting,
                  onViewProfile: () => profileTaps++,
                  onAction: enabled ? () => actionTaps++ : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder chipOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(Container)).first;

  Finder buttonOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(AppButton));

  testWidgets('칩은 서버가 준 남은 날 그대로 "5일 남음" — 회색 칩 · muted 글자 · 타이머 아이콘', (tester) async {
    await pump(tester, _card());

    final decoration = tester.widget<Container>(chipOf('5일 남음')).decoration! as BoxDecoration;
    expect(decoration.color, AppColors.surfaceStrong);
    expect(tester.widget<Text>(find.text('5일 남음')).style?.color, AppColors.muted);
    final icon = tester.widget<Icon>(find.descendant(of: chipOf('5일 남음'), matching: find.byType(Icon)));
    expect((icon.icon, icon.color), (AppIcons.timer, AppColors.muted));
  });

  testWidgets('남은 날이 1(24시간 이하)이면 "오늘 마감" — primary-wash 칩 · primary-text 아이콘 · 글자(pen wqlyd)', (tester) async {
    await pump(tester, _card(daysLeft: 1));

    expect(find.text('1일 남음'), findsNothing);
    final decoration = tester.widget<Container>(chipOf('오늘 마감')).decoration! as BoxDecoration;
    expect(decoration.color, AppColors.primaryWash);
    expect(tester.widget<Text>(find.text('오늘 마감')).style?.color, AppColors.primaryText);
    final icon = tester.widget<Icon>(find.descendant(of: chipOf('오늘 마감'), matching: find.byType(Icon)));
    expect(icon.color, AppColors.primaryText);
  });

  testWidgets('이름은 ink(끝난 신청처럼 흐리지 않는다), 줄 높이 72 · 줄 → 12 → 버튼 44 두 개 · 사이 8 · 같은 폭', (tester) async {
    await pump(tester, _card());

    expect(tester.widget<Text>(find.text('여우비, 23')).style?.color, AppColors.ink);
    final profile = tester.getRect(buttonOf('프로필 보기'));
    final reapply = tester.getRect(buttonOf('다시 신청하기'));
    expect(profile.top - 72, 12);
    expect((profile.height, reapply.height), (44.0, 44.0));
    expect(reapply.left - profile.right, 8);
    expect(profile.width, reapply.width);
    expect((profile.left, reapply.right), (0.0, 328.0));
    expect(tester.getSize(find.byType(RejectedCardRow)).height, 72 + 12 + 44);
  });

  testWidgets('[프로필 보기] 는 보조(surface-strong · ink), [다시 신청하기] 는 primary — 둘 다 작은 크기', (tester) async {
    await pump(tester, _card());

    final profile = tester.widget<AppButton>(buttonOf('프로필 보기'));
    final reapply = tester.widget<AppButton>(buttonOf('다시 신청하기'));
    expect((profile.variant, profile.size), (AppButtonVariant.tonal, AppButtonSize.small));
    expect((reapply.variant, reapply.size), (AppButtonVariant.primary, AppButtonSize.small));
  });

  testWidgets('받은 신청을 거절한 줄은 오른쪽 버튼이 [수락하기]', (tester) async {
    await pump(tester, _card(source: RejectedSource.acceptance));

    expect(buttonOf('수락하기'), findsOneWidget);
    expect(find.text('다시 신청하기'), findsNothing);
  });

  testWidgets('버튼을 누르면 각자의 일을 부른다 — 줄 위쪽은 눌리지 않는다', (tester) async {
    await pump(tester, _card());

    await tester.tap(find.text('여우비, 23'), warnIfMissed: false);
    expect((profileTaps, actionTaps), (0, 0));
    expect(find.descendant(of: find.byType(RequestRowFrame), matching: find.byType(InkWell)), findsNothing);
    await tester.tap(find.text('프로필 보기'));
    await tester.tap(find.text('다시 신청하기'));
    expect((profileTaps, actionTaps), (1, 1));
  });

  testWidgets('다른 줄을 보내는 중이면 오른쪽 버튼만 꺼진다 — [프로필 보기] 는 그대로', (tester) async {
    await pump(tester, _card(), enabled: false);

    expect(tester.widget<AppButton>(buttonOf('다시 신청하기')).onPressed, isNull);
    expect(tester.widget<AppButton>(buttonOf('프로필 보기')).onPressed, isNotNull);
  });

  testWidgets('이 줄을 보내는 중이면 오른쪽 버튼이 도는 표시가 된다', (tester) async {
    await pump(tester, _card(source: RejectedSource.acceptance), enabled: false, submitting: true);

    final accept = tester.widget<AppButton>(find.byType(AppButton).last);
    expect(accept.isLoading, isTrue);
  });
}
