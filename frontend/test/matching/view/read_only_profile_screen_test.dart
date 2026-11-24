import 'dart:async';

import 'package:campus_mate/chat/model/repository/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/card_action_bar.dart';
import 'package:campus_mate/common/widgets/retry_notice.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/matching/model/data/card_detail.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/profile_avatar_header.dart';
import 'package:campus_mate/matching/view/read_only_profile_screen.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/model/repository/fake_chat_repository.dart';
import '../model/repository/fake_card_repository.dart';

final _detail = CardDetail(
  cardId: 'card-1',
  profile: const CardProfile(profileId: 't1', nickname: '여우비', age: 23, university: '테스트대학교', major: '컴퓨터공학과'),
  survey: List.filled(9, 0.5),
  animalType: AnimalType.cat,
  impressionType: ImpressionType.chic,
  religion: Religion.none,
  isSmoker: false,
  interests: const ['등산'],
  myTraits: const ['유머러스'],
  idealTraits: const ['다정한'],
  mbti: 'ENFP',
  studentNumber: '20',
);

/// 10b-2 보낸 신청 · 프로필 보기(읽기 전용, pen ig7i2 — UI값표 CT5Lq 16-2). 20-5 hhlWE(거절한 카드)가 제목 · 아래 버튼만 바꿔 같이 쓴다.
void main() {
  Future<FakeCardRepository> pump(
    WidgetTester tester, {
    Result<CardDetail>? card,
    Widget? bottomAction,
    Completer<void>? hold,
    Result<CardDetail>? acceptance,
  }) async {
    final repository = FakeCardRepository()
      ..card = card ?? Success(_detail)
      ..acceptanceDetail = acceptance
      ..holdCard = hold;
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReadOnlyProfileScreen(
            cardId: 'card-1',
            title: '보낸 신청',
            bottomAction: bottomAction,
            readsAcceptance: acceptance != null,
          ),
        ),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('앱바 제목은 넘겨 준 글자 18/700 ink(AppBar · Sub `KH1hX` 제목 `YSMvI`)', (tester) async {
    await pump(tester);

    final title = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.text('보낸 신청')));
    expect(title.style?.fontSize, 18);
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.color, AppColors.ink);
  });

  testWidgets('본문은 10b 와 같은 카드(아바타 칸 + 이름 · 성향 · 태그)다', (tester) async {
    await pump(tester);

    final card = tester.widget<ProfileCard>(find.byType(ProfileCard));
    expect(card.header, isA<ProfileAvatarHeader>());
    expect(find.text('여우비, 23'), findsOneWidget);
    expect(find.text('ENFP'), findsOneWidget);
    // 본문 좌우 16, 카드가 앱바 바로 아래에 붙는다(pen ZGYbU padding [0,16]).
    final cardRect = tester.getRect(find.byType(ProfileCard));
    expect(cardRect.left, 16);
    expect(cardRect.top, tester.getBottomLeft(find.byType(AppBar)).dy);
  });

  testWidgets('결정 버튼이 없다(pen iGKTj 끔) — 거절 · 대화 신청하기가 보이지 않는다', (tester) async {
    await pump(tester);

    expect(find.byType(CardActionBar), findsNothing);
    expect(find.text('거절'), findsNothing);
    expect(find.text('대화 신청하기'), findsNothing);
  });

  testWidgets('하단 내비는 대화 탭 선택(pen cT6qP)', (tester) async {
    await pump(tester);

    expect(tester.widget<AppBottomNav>(find.byType(AppBottomNav)).current, AppTab.chat);
  });

  testWidgets('아래 버튼을 넘기면 카드 아래 14 에 함께 스크롤한다(20-5 hhlWE 자리)', (tester) async {
    await pump(tester, bottomAction: const SizedBox(key: Key('action'), height: 56));

    await tester.scrollUntilVisible(find.byKey(const Key('action')), 200);
    expect(
      tester.getTopLeft(find.byKey(const Key('action'))).dy - tester.getBottomLeft(find.byType(ProfileCard)).dy,
      14,
    );
  });

  testWidgets('읽는 중에는 도는 표시만 있다', (tester) async {
    final hold = Completer<void>();
    await pump(tester, hold: hold);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ProfileCard), findsNothing);
    hold.complete();
    await tester.pump();
  });

  // 대장 판정 16-2: 숨김 · 없음(서버 404 "카드를 찾을 수 없어요" — 앱에는 서버 문구를 든 거절로 온다)은 다시 해도 같으므로
  // 10b 처럼 가운데 회색 글자만. 연결 실패 같은 나머지는 RetryNotice.
  for (final failure in const <Failure>[ServerRejectedFailure('카드를 찾을 수 없어요'), NotFoundFailure()]) {
    testWidgets('${failure.runtimeType}: 10b 와 같은 회색 글자(DetailMessage)만, 다시 시도 없음', (tester) async {
      await pump(tester, card: FailureResult(failure));

      expect(find.byType(DetailMessage), findsOneWidget);
      expect(find.byType(RetryNotice), findsNothing);
      expect(find.text('다시 시도'), findsNothing);
      expect(find.byType(ProfileCard), findsNothing);
    });
  }

  testWidgets('연결 실패면 RetryNotice 로 알리고 다시 시도하면 카드를 그린다', (tester) async {
    final repository = await pump(tester, card: const FailureResult(NetworkFailure()));

    expect(find.byType(RetryNotice), findsOneWidget);
    expect(find.byType(ProfileCard), findsNothing);

    repository.card = Success(_detail);
    await tester.tap(find.text('다시 시도'));
    await tester.pump();

    expect(find.byType(ProfileCard), findsOneWidget);
  });

  // 20-5: 받은 신청을 거절한 줄은 카드 주인이 상대라 `GET /cards/{id}` 가 404 다 — 받은 신청 읽기(`GET /cards/acceptances/{id}`)로 연다.
  group('받은 신청 읽기(readsAcceptance)', () {
    testWidgets('카드 읽기가 아니라 받은 신청 읽기로 그린다', (tester) async {
      await pump(tester, card: const FailureResult(NotFoundFailure()), acceptance: Success(_detail));
      await tester.pump();

      expect(find.byType(ProfileCard), findsOneWidget);
      expect(find.byType(DetailMessage), findsNothing);
    });

    testWidgets('연결 실패면 RetryNotice, 다시 시도하면 받은 신청을 다시 읽어 그린다', (tester) async {
      final repository = await pump(tester, acceptance: const FailureResult(NetworkFailure()));
      await tester.pump();
      expect(find.byType(RetryNotice), findsOneWidget);

      repository.acceptanceDetail = Success(_detail);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(ProfileCard), findsOneWidget);
    });

    testWidgets('서버 거절(이미 답함 · 기한 지남)은 회색 글자만', (tester) async {
      await pump(tester, acceptance: const FailureResult(ServerRejectedFailure('이미 답한 수락이에요')));
      await tester.pump();

      expect(find.byType(DetailMessage), findsOneWidget);
      expect(find.byType(RetryNotice), findsNothing);
    });
  });
}
