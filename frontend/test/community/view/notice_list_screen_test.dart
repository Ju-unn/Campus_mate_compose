import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/glass_bottom_nav.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/community/model/data/feed_page.dart';
import 'package:campus_mate/community/model/repository/community_repository_provider.dart';
import 'package:campus_mate/community/view/community_card_parts.dart';
import 'package:campus_mate/community/view/notice_list_screen.dart';
import 'package:campus_mate/community/view/notice_row.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/repository/fake_chat_repository.dart';
import '../../matching/model/repository/fake_card_repository.dart';
import '../model/repository/fake_community_repository.dart';

/// 17g 공지사항 목록(pen `unXUa`) · 빈 상태(`nA4tm`).
void main() {
  late FakeCommunityRepository repository;

  setUp(() => repository = FakeCommunityRepository());

  Future<void> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(
          path: '/community',
          builder: (context, state) => Center(
            child: TextButton(onPressed: () => context.push('/community/notices'), child: const Text('열기')),
          ),
        ),
        GoRoute(path: '/community/notices', builder: (context, state) => const NoticeListScreen()),
        GoRoute(
          path: '/community/notices/:noticeId',
          builder: (context, state) => Text('공지 상세 ${state.pathParameters['noticeId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          communityRepositoryProvider.overrideWithValue(repository),
          // 하단 내비 뱃지가 대화 목록 · 수락함을 읽는다.
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('앱바 "공지사항" + 뒤로, 공지 줄 사이 구분선, 하단 내비(커뮤니티 선택)가 보인다', (tester) async {
    repository.noticePage = Success(FeedPage(
      items: [noticeFixture(id: 'n2', title: '새 공지', isNew: true), noticeFixture(title: '옛 공지')],
      hasMore: false,
    ));
    await pump(tester);

    expect(find.text('공지사항'), findsOneWidget);
    expect(find.byTooltip('뒤로'), findsOneWidget);
    expect(find.byType(NoticeRow), findsNWidgets(2));
    expect(find.byType(CommunityCardSeparator), findsOneWidget);
    expect(tester.widget<GlassBottomNav>(find.byType(GlassBottomNav)).current, AppTab.community);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, AppColors.canvas);
  });

  testWidgets('공지가 없으면 "아직 공지가 없어요" + 마스코트(pen `nA4tm`)', (tester) async {
    await pump(tester);

    expect(find.byType(EmptyNotice), findsOneWidget);
    expect(find.text('아직 공지가 없어요'), findsOneWidget);
    expect(find.byType(NoticeRow), findsNothing);
  });

  testWidgets('못 읽으면 다시 시도를 두고, 누르면 다시 읽는다', (tester) async {
    repository.noticePage = const FailureResult(NetworkFailure());
    await pump(tester);
    expect(find.byType(RetryNotice), findsOneWidget);

    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: false));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.byType(NoticeRow), findsOneWidget);
    expect(repository.noticeRequests, hasLength(2));
  });

  testWidgets('줄을 누르면 그 공지 상세로 간다', (tester) async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture(id: 'n7')], hasMore: false));
    await pump(tester);

    await tester.tap(find.byType(NoticeRow));
    await tester.pumpAndSettle();

    expect(find.text('공지 상세 n7'), findsOneWidget);
  });

  testWidgets('끝까지 내리면 맨 아래 공지 다음 쪽을 이어 받는다', (tester) async {
    repository
      ..noticePage = Success(FeedPage(items: [for (var i = 0; i < 20; i++) noticeFixture(id: 'n$i')], hasMore: true))
      ..nextNoticePage = Success(FeedPage(items: [noticeFixture(id: 'old')], hasMore: false));
    await pump(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();

    expect(repository.noticeRequests.last.beforeId, 'n19');
    expect(find.byKey(const ValueKey('notice-old')), findsOneWidget);
  });

  testWidgets('아래로 당기면 다시 읽는다', (tester) async {
    repository.noticePage = Success(FeedPage(items: [noticeFixture()], hasMore: false));
    await pump(tester);

    await tester.fling(find.byType(ListView), const Offset(0, 500), 1500);
    await tester.pumpAndSettle();

    expect(repository.noticeRequests, hasLength(2));
  });
}
