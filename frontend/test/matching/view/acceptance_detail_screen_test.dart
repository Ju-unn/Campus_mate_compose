import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/acceptance_detail_screen.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/profile_avatar_header.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../model/fake_card_repository.dart';

const _profile = CardProfile(
  profileId: 'p1',
  nickname: '초코라떼',
  age: 25,
  university: '고려대학교',
  major: '경영학과',
  avatarUrl: 'https://img.test/a.png',
);

const _acceptance = Acceptance(cardId: 'card-1', profile: _profile);

final _detail = CardDetail(
  cardId: 'card-1',
  profile: _profile,
  survey: List.filled(9, 0.5),
  animalType: AnimalType.cat,
  impressionType: ImpressionType.chic,
  religion: Religion.none,
  isSmoker: false,
  interests: const ['등산', '영화'],
  myTraits: const ['유머러스'],
  idealTraits: const ['다정한'],
  mbti: 'ENFP',
  bio: '주말엔 산책해요',
);

/// 받은 신청 · 프로필 보기(pen `o4QqYR`, 사용자 결정 10-16): 행의 "프로필 보기" 가 연다.
/// 앱바 "받은 신청" · 카드(아바타 칸 + 10b 와 같은 본문) · 하단 고정 바(거절 104×56 · 수락하기 56).
/// 수락은 확인 창 없이 바로 보내고, 성사되면 12 로, 아니면 목록으로 돌아가 목록을 다시 읽는다. 거절도 바로 보내고 목록으로.
void main() {
  late FakeCardRepository repository;
  late GoRouter router;

  /// 목록 자리(가짜 화면) → `/acceptances/card-1` push. [list] 가 있으면 진짜 대화 탭을 목록 자리에 둔다.
  Future<ProviderContainer> open(WidgetTester tester, {bool realList = false, bool settle = true}) async {
    final container = ProviderContainer(overrides: [
      cardRepositoryProvider.overrideWithValue(repository),
      chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      universityLogosProvider.overrideWith((ref) => const <String, String>{}),
    ]);
    addTearDown(container.dispose);
    router = GoRouter(
      initialLocation: AppRoutes.conversations,
      routes: [
        GoRoute(
          path: AppRoutes.conversations,
          builder: (context, state) => realList
              ? const ConversationsScreen()
              : Scaffold(
                  body: TextButton(
                    onPressed: () => context.push('${AppRoutes.acceptanceDetail}/card-1'),
                    child: const Text('목록'),
                  ),
                ),
        ),
        GoRoute(
          path: '${AppRoutes.acceptanceDetail}/:cardId',
          builder: (context, state) => AcceptanceDetailScreen(cardId: state.pathParameters['cardId']!),
        ),
        GoRoute(
          path: AppRoutes.matchMade,
          builder: (context, state) {
            final args = state.extra! as MatchMadeArgs;
            return Text('매칭 ${args.nickname} ${args.matchId}');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    // 목록은 이미 한 번 읽혀 있다(행의 닉네임이 12 화면 재료다).
    await container.read(acceptancesViewModelProvider.notifier).refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.text(realList ? '프로필 보기' : '목록'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  setUp(() {
    repository = FakeCardRepository()
      ..acceptances = const Success([_acceptance])
      ..acceptanceDetail = Success(_detail);
  });

  Finder button(String label) => find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton));

  group('그림(pen `o4QqYR`)', () {
    testWidgets('앱바 제목 "받은 신청", 뒤로 화살표, 하단 내비 없음', (tester) async {
      await open(tester);

      expect(find.descendant(of: find.byType(AppBar), matching: find.text('받은 신청')), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('카드 맨 위 아바타 칸 → 이름 · 나이 · 학교 → 10b 와 같은 본문(자기소개 · 성향 · 태그)', (tester) async {
      await open(tester);

      expect(repository.acceptanceDetailReads, ['card-1']);
      final card = tester.widget<ProfileCard>(find.byType(ProfileCard));
      expect(card.header, isA<ProfileAvatarHeader>());
      expect((card.header! as ProfileAvatarHeader).url, 'https://img.test/a.png');
      expect(find.text('초코라떼, 25'), findsOneWidget);
      expect(find.text('고려대학교 경영학과'), findsOneWidget);
      expect(find.text('주말엔 산책해요'), findsOneWidget);
      expect(tester.getTopLeft(find.text('초코라떼, 25')).dy, greaterThan(tester.getBottomLeft(find.byType(ProfileAvatarHeader)).dy - 1));
    });

    testWidgets('하단 고정 바: 거절(x · 104×56 · secondary) + 수락하기(check · 남은 폭 · 56 · primary), 스크롤해도 제자리', (tester) async {
      await open(tester);

      final reject = tester.getRect(button('거절'));
      final accept = tester.getRect(button('수락하기'));
      expect(reject.size, const Size(104, 56));
      expect(accept.height, 56);
      expect(accept.left - reject.right, 12);
      expect(accept.top, reject.top);
      expect(find.descendant(of: button('거절'), matching: find.byIcon(AppIcons.x)), findsOneWidget);
      expect(find.descendant(of: button('수락하기'), matching: find.byIcon(AppIcons.check)), findsOneWidget);
      // 색은 토큰 — 거절 = secondary(primary-disabled 채움 · ink 글자), 수락하기 = primary(흰 글자).
      Color? fill(String label) =>
          tester.widget<ElevatedButton>(button(label)).style!.backgroundColor!.resolve(const <WidgetState>{});
      Color? ink(String label) =>
          tester.widget<ElevatedButton>(button(label)).style!.foregroundColor!.resolve(const <WidgetState>{});
      expect((fill('거절'), ink('거절')), (AppColors.primaryDisabled, AppColors.ink));
      expect((fill('수락하기'), ink('수락하기')), (AppColors.primary, AppColors.onPrimary));
      // 바는 스크롤 밖이다.
      expect(find.ancestor(of: find.text('수락하기'), matching: find.byType(Scrollable)), findsNothing);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getRect(button('수락하기')), accept);
    });

    testWidgets('낭독기에는 "거절" · "수락하기" 버튼으로 읽힌다', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);

      for (final label in ['거절', '수락하기']) {
        final node = tester.getSemantics(button(label));
        expect(node.label, label);
        expect(node.flagsCollection.isButton, isTrue, reason: label);
      }
      semantics.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale 에서 하단 바가 넘치거나 글자가 잘리지 않는다', (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await open(tester);

        expect(tester.takeException(), isNull);
        for (final label in ['거절', '수락하기']) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.size.height, greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.5),
              reason: label);
          expect(paragraph.size.width, greaterThanOrEqualTo(paragraph.getMinIntrinsicWidth(double.infinity) - 0.5),
              reason: label);
        }
        // 두 버튼은 같이 커진다.
        expect(tester.getRect(button('거절')).height, tester.getRect(button('수락하기')).height);
      });
    }
  });

  group('읽는 중 · 읽기 실패(pen 에 없는 상태 — 10b 와 같은 모양)', () {
    testWidgets('읽는 동안은 가운데 도는 표시만 있고 결정 바가 없다', (tester) async {
      repository.holdAcceptanceDetail = Completer<void>();
      await open(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('수락하기'), findsNothing);
      repository.holdAcceptanceDetail!.complete();
      await tester.pumpAndSettle();
      expect(find.text('수락하기'), findsOneWidget);
    });

    for (final message in ['수락을 찾을 수 없어요', '이미 답한 수락이에요', '기한이 지났어요']) {
      testWidgets('읽기 실패 "$message" 는 그 문구를 가운데에 두고 결정 바가 없다', (tester) async {
        repository.acceptanceDetail = FailureResult(ServerRejectedFailure(message));
        await open(tester);

        expect(find.text(message), findsOneWidget);
        expect(find.byType(ProfileCard), findsNothing);
        expect(find.text('수락하기'), findsNothing);
        expect(find.text('거절'), findsNothing);
      });
    }
  });

  group('결정(확인 창 없이 바로)', () {
    testWidgets('수락하기 → 바로 accept 를 보내고, 성사되면 12 로 바뀐다 — 뒤로 가면 목록이다', (tester) async {
      repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: true, matchId: 'm-1'));
      await open(tester);

      await tester.tap(find.text('수락하기'));
      await tester.pumpAndSettle();

      expect(repository.decisions.single, (cardId: 'card-1', decision: CardDecision.accept));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('매칭 초코라떼 m-1'), findsOneWidget);
      expect(find.byType(AcceptanceDetailScreen), findsNothing);
      // 12 가 이 화면 자리를 바꿔 들어왔다 — 한 번 닫으면 목록이다.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('목록'), findsOneWidget);
    });

    testWidgets('수락했는데 성사가 아니면 목록으로 돌아가고 목록을 다시 읽는다', (tester) async {
      repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: false));
      await open(tester);
      final readsBefore = repository.fetchAcceptancesCount;

      await tester.tap(find.text('수락하기'));
      await tester.pumpAndSettle();

      expect(repository.decisions.single.decision, CardDecision.accept);
      expect(find.text('목록'), findsOneWidget);
      expect(find.textContaining('매칭'), findsNothing);
      expect(repository.fetchAcceptancesCount, readsBefore + 1);
    });

    testWidgets('거절 → 바로 reject 를 보내고 목록으로 돌아가 목록을 다시 읽는다', (tester) async {
      await open(tester);
      final readsBefore = repository.fetchAcceptancesCount;

      await tester.tap(find.text('거절'));
      await tester.pumpAndSettle();

      expect(repository.decisions.single, (cardId: 'card-1', decision: CardDecision.reject));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('목록'), findsOneWidget);
      expect(repository.fetchAcceptancesCount, readsBefore + 1);
    });

    testWidgets('보내는 동안 두 버튼이 꺼지고, 다시 눌러도 한 번만 간다', (tester) async {
      repository.holdRespond = Completer<void>();
      await open(tester);

      await tester.tap(find.text('수락하기'));
      await tester.pump();
      await tester.tap(find.text('수락하기'), warnIfMissed: false);
      await tester.tap(find.text('거절'), warnIfMissed: false);
      await tester.pump();

      expect(tester.widget<ElevatedButton>(button('수락하기')).onPressed, isNull);
      expect(tester.widget<ElevatedButton>(button('거절')).onPressed, isNull);
      repository.holdRespond!.complete();
      await tester.pumpAndSettle();
      expect(repository.decisions, hasLength(1));
    });

    testWidgets('보내기가 실패하면(410) 이 화면에 남아 서버 문구를 보이고 버튼이 다시 켜진다', (tester) async {
      repository.acceptanceOutcome = const FailureResult(ServerRejectedFailure('기한이 지났어요'));
      await open(tester);

      await tester.tap(find.text('수락하기'));
      await tester.pumpAndSettle();

      expect(find.byType(AcceptanceDetailScreen), findsOneWidget);
      expect(find.text('기한이 지났어요'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(button('수락하기')).onPressed, isNotNull);
    });

    testWidgets('목록 쪽에 남아 있던 오류 문구는 이 화면에 옮겨 오지 않는다 — 여기서 보낸 결정의 실패만 보인다', (tester) async {
      final container = await open(tester);
      repository.acceptances = const FailureResult(NetworkFailure());
      await container.read(acceptancesViewModelProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text('네트워크 연결을 확인해 주세요'), findsNothing);
    });
  });

  group('진짜 대화 탭에서', () {
    testWidgets('행의 "프로필 보기" → 이 화면, 수락 성사 → 12 가 한 번만 뜨고 닫으면 대화 탭', (tester) async {
      repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: true, matchId: 'm-1'));
      await open(tester, realList: true);

      expect(find.byType(AcceptanceDetailScreen), findsOneWidget);
      await tester.tap(find.text('수락하기'));
      await tester.pumpAndSettle();

      expect(find.text('매칭 초코라떼 m-1'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ConversationsScreen), findsOneWidget);
      expect(find.text('매칭 초코라떼 m-1'), findsNothing);
      expect(router.canPop(), isFalse);
    });
  });
}
