import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/daily_card.dart';
import 'package:campus_mate/matching/view/today_cards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../model/fake_card_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakeCardRepository repository,
      [FakeChatRepository? chat, HomeSummary? summary]) async {
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        // 하단 내비 뱃지가 안 읽은 메시지 수를 읽는다(§8.8).
        chatRepositoryProvider.overrideWithValue(chat ?? FakeChatRepository()),
        // 우리 학교가 모집 중인지 홈 요약으로 본다(19 코호트). 기본은 요약 없음 = 지금 그대로.
        homeRepositoryProvider.overrideWithValue(
          FakeHomeRepository(summary == null ? const FailureResult(NetworkFailure()) : Success(summary)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TodayCardsScreen()),
      ),
    );
    await tester.pump();
  }

  group('19 코호트 — 모집 중이면 오늘 탭도 대기 화면(계획서 결정 6 · 11)', () {
    HomeSummary summaryWith(CohortWait? cohort) => HomeSummary(
      presentPeopleImages: const [],
      deliveredCards: 0,
      signups: 0,
      conversationsStarted: 0,
      reviewRating: 4.8,
      reviewCount: 143,
      campuses: const [],
      profileCompletionPercent: 60,
      cohort: cohort,
    );

    final cardRepository = FakeCardRepository()
      ..today = const Success(
        TodayCards(
          cards: [
            DailyCard(
              cardId: 'card-1',
              source: CardSource.daily,
              profile: CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
            ),
          ],
        ),
      );

    testWidgets('cohort 가 있으면 본문이 대기 화면이고 카드는 없다. 앱바 · 내비는 오늘 탭 것', (tester) async {
      final cohort = CohortWait(firstCardAt: DateTime.now().add(const Duration(days: 3)), recruitCount: 5);
      await pump(tester, cardRepository, null, summaryWith(cohort));

      expect(find.byType(CohortWaitView), findsOneWidget);
      expect(find.text('여우비, 23'), findsNothing);
      expect(find.text('오늘의 카드'), findsOneWidget);
      expect(tester.widget<AppBottomNav>(find.byType(AppBottomNav)).current, AppTab.today);
    });

    testWidgets('cohort 가 null 이면 지금 그대로 카드를 보여준다', (tester) async {
      await pump(tester, cardRepository, null, summaryWith(null));

      expect(find.byType(CohortWaitView), findsNothing);
      expect(find.text('여우비, 23'), findsOneWidget);
    });
  });

  testWidgets('카드가 있으면 닉네임·나이와 학교 줄을 보여준다', (tester) async {
    final repository = FakeCardRepository()
      ..today = const Success(
        TodayCards(
          cards: [
            DailyCard(
              cardId: 'card-1',
              source: CardSource.daily,
              profile: CardProfile(
                profileId: 't1',
                nickname: '여우비',
                age: 23,
                university: '테스트대학교',
                major: '컴퓨터공학과',
              ),
            ),
          ],
        ),
      );

    await pump(tester, repository);

    expect(find.text('여우비, 23'), findsOneWidget);
    expect(find.text('테스트대학교 · 컴퓨터공학과'), findsOneWidget);
    expect(find.text('프로필 자세히 보기'), findsOneWidget);
  });

  testWidgets('후보 풀이 비면 11b 문구와 알림 안내를 보여준다', (tester) async {
    final repository = FakeCardRepository()
      ..today = const Success(TodayCards(cards: [], candidatePoolEmpty: true));

    await pump(tester, repository);

    expect(find.text('지금은 소개할 사람이 없어요'), findsOneWidget);
    expect(find.text('새로운 사람이 오면 알림을 보내드려요'), findsOneWidget);
  });

  testWidgets('오늘 몫이 끝나면 카운트다운과 "내일 만날 사람들" 띠를 보여준다', (tester) async {
    // pen `i4VFS` — 띠는 눌러도 열리지 않는다는 말까지 같이 보여준다.
    final repository = FakeCardRepository()
      ..today = Success(TodayCards(cards: const [], nextIssueAt: DateTime.now().add(
        const Duration(hours: 3),
      )));

    await pump(tester, repository);

    expect(find.text('오늘 카드는 확인했어요'), findsOneWidget);
    expect(find.text('내일 만날 사람들'), findsOneWidget);
    expect(find.text('탭해도 열리지 않아요'), findsOneWidget);
  });

  group('대기 부제 — 다음 주면 "다음 주 O요일"(사용자 결정 10-04 (나), 주는 서울 월요일 시작)', () {
    // 서울 시각을 UTC 로 만든다 — 기기 시간대에 기대지 않는다. 2026-10-05 가 월요일.
    DateTime seoul(int day, int hour) => DateTime.utc(2026, 10, day, hour).subtract(const Duration(hours: 9));

    test('주 1회(월) — 월요일에 받고 나면 다음 주 월요일', () {
      expect(waitingSubtitle(seoul(12, 7), seoul(5, 12)), '다음 주 월요일 오전 7시에 새로운 사람을 찾아볼게요');
    });

    test('주 2회(월 · 목) — 월요일 → 같은 주 목요일, 목요일 → 다음 주 월요일', () {
      expect(waitingSubtitle(seoul(8, 7), seoul(5, 12)), '목요일 오전 7시에 새로운 사람을 찾아볼게요');
      expect(waitingSubtitle(seoul(12, 7), seoul(8, 12)), '다음 주 월요일 오전 7시에 새로운 사람을 찾아볼게요');
    });

    test('주 3회(월 · 수 · 금) — 같은 주 금요일 → 다음 주 월요일', () {
      expect(waitingSubtitle(seoul(7, 7), seoul(5, 12)), '수요일 오전 7시에 새로운 사람을 찾아볼게요');
      expect(waitingSubtitle(seoul(12, 7), seoul(9, 12)), '다음 주 월요일 오전 7시에 새로운 사람을 찾아볼게요');
    });

    test('주 4회(월 · 수 · 금 · 일) — 금요일 → 같은 주 일요일', () {
      expect(waitingSubtitle(seoul(11, 7), seoul(9, 12)), '일요일 오전 7시에 새로운 사람을 찾아볼게요');
    });

    test('일요일 → 월요일은 하루 남았으니 "내일"(대장 (가), 사용자 확인 대기)', () {
      expect(waitingSubtitle(seoul(12, 7), seoul(11, 12)), '내일 오전 7시에 새로운 한 명이 도착해요');
    });

    test('주 경계는 서울 날짜 — UTC 로는 일요일이어도 서울이 월요일이면 같은 주 목요일', () {
      // 서울 월요일 05:00 = UTC 일요일 20:00.
      expect(waitingSubtitle(seoul(15, 7), seoul(12, 5)), '목요일 오전 7시에 새로운 사람을 찾아볼게요');
    });
  });
}
