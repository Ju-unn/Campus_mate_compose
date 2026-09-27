import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/poll_card.dart';
import 'package:campus_mate/community/view/poll_detail_screen.dart';
import 'package:campus_mate/community/view/poll_donut.dart';
import 'package:campus_mate/community/view/poll_time.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_community_repository.dart';

void main() {
  late FakeCommunityRepository repository;

  setUp(() => repository = FakeCommunityRepository());

  /// 피드 목록을 먼저 채운 뒤 피드 위에 17c 를 연다(들어오는 길이 피드 하나뿐이다).
  Future<void> pumpDetail(WidgetTester tester, String pollId) async {
    final container = ProviderContainer(
      overrides: [
        communityRepositoryProvider.overrideWithValue(repository),
        communityNowProvider.overrideWithValue(() => DateTime(2026, 9, 27, 14)),
      ],
    );
    addTearDown(container.dispose);
    container.read(communityFeedViewModelProvider);
    await container.read(communityFeedViewModelProvider.notifier).refresh();

    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(path: '/community', builder: (context, state) => const Text('피드')),
        GoRoute(
          path: '/community/polls/:pollId',
          builder: (context, state) => PollDetailScreen(pollId: state.pathParameters['pollId']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    router.push('/community/polls/$pollId');
    await tester.pumpAndSettle();
  }

  testWidgets('17c: 제목 "투표 상세", 피드 카드와 같은 크기, 질문 전문, 댓글 안내', (tester) async {
    repository.page = Success(PollPage(polls: [pollFixture(question: '가' * 80, myChoice: PollChoice.a)], hasMore: false));
    await pumpDetail(tester, 'p1');
    expect(find.text('투표 상세'), findsOneWidget);
    expect(tester.getSize(find.byType(PollDonut)), const Size(96, 96));
    expect(find.text('자세히 보기'), findsNothing);
    expect(tester.widget<Text>(find.text('가' * 80)).maxLines, isNull);
    expect(find.text('댓글 기능은 아직 준비 중이에요'), findsOneWidget);
  });

  testWidgets('상세에서도 투표 전이면 투표할 수 있다(사용자 결정 4)', (tester) async {
    repository
      ..page = Success(PollPage(polls: [pollFixture()], hasMore: false))
      ..voteResult = Success(VoteOutcome(poll: pollFixture(myChoice: PollChoice.b), rewarded: false));
    await pumpDetail(tester, 'p1');
    await tester.tap(find.bySemanticsLabel('반대'));
    await tester.pumpAndSettle();
    expect(repository.votes.single.choice, PollChoice.b);
    expect(find.byType(PollDonut), findsOneWidget);
  });

  testWidgets('목록에서 빠진 글이면 찾을 수 없다고 말한다', (tester) async {
    await pumpDetail(tester, 'gone');
    expect(find.text('질문을 찾을 수 없어요'), findsOneWidget);
  });

  testWidgets('pen 17c: 제목 x60 · 뒤로 arrow-left 22, 본문 안쪽 16, 카드 249, 댓글 안내는 카드 아래 16(bcnJx · ZR52B · v9Pmy0 · LyR5Y)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository.page = Success(PollPage(polls: [pollFixture(myChoice: PollChoice.a)], hasMore: false));
    await pumpDetail(tester, 'p1');

    expect(tester.getTopLeft(find.text('투표 상세')).dx, 60);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.arrowLeft)).size, 22);
    final card = tester.getRect(find.byType(PollCard));
    expect(card.topLeft, const Offset(16, 56 + 16));
    expect(card.width, 328);
    expect(card.height, closeTo(249, 2));
    expect(tester.getRect(find.text('댓글 기능은 아직 준비 중이에요')).top - card.bottom, 16);
  });
}
