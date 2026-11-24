import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/data/acceptance.dart';
import 'package:campus_mate/matching/model/data/card_profile.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/model/repository/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/rejected_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/rejected_cards_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_card_repository.dart';

const _mine = RejectedCard(
  cardId: 'card-1',
  source: RejectedSource.card,
  daysLeft: 6,
  profile: CardProfile(nickname: '여우비', age: 23),
);

const _received = RejectedCard(
  cardId: 'card-2',
  source: RejectedSource.acceptance,
  daysLeft: 3,
  profile: CardProfile(nickname: '봄비', age: 22),
);

const _both = Success(RejectedCards([_mine, _received]));

// 다시 신청 · 되돌리기의 404 · 409 — 문구가 있는 4xx 는 http 층이 ServerRejectedFailure 로 만든다(http_send `_toRejection`).
// 앱은 문구로 가르지 않는다(대장 결정 11-24) — 아래 문구는 화면에 그대로 보일 서버 글자일 뿐이다.
const _cardGone = FailureResult<void>(ServerRejectedFailure('카드를 찾을 수 없어요'));
const _cardDecided = FailureResult<void>(ServerRejectedFailure('이미 결정한 카드예요'));
const _answered = FailureResult<AcceptanceOutcome>(ServerRejectedFailure('이미 답한 수락이에요'));

/// 오류 칸에 담긴 서버 문구. 서버 거절이 아니면 null.
String? serverTextOf(Failure? failure) => failure is ServerRejectedFailure ? failure.serverMessage : null;

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(repository)]);
  });

  tearDown(() => container.dispose());

  RejectedCardsViewModel viewModel() => container.read(rejectedCardsViewModelProvider.notifier);

  RejectedCardsUiState state() => container.read(rejectedCardsViewModelProvider);

  List<String> rowIds() => state().cards.toList().map((card) => card.cardId).toList();

  Future<void> loaded() async {
    viewModel();
    await pumpEventQueue();
  }

  group('목록 읽기', () {
    test('만들어지면 읽기 시작하고, 읽으면 서버 목록을 그대로 담는다', () async {
      repository.rejected = _both;

      expect(state().isLoading, isTrue);
      await loaded();

      expect(state().isLoading, isFalse);
      expect(rowIds(), ['card-1', 'card-2']);
      expect(state().error, isNull);
      expect(repository.fetchRejectedCount, 1);
    });

    test('처음 읽기가 실패하면 로딩을 끝내고 오류를 보인다', () async {
      repository.rejected = const FailureResult(NetworkFailure());

      await loaded();

      expect(state().isLoading, isFalse);
      expect(state().error, isA<NetworkFailure>());
    });

    test('조용한 다시 읽기가 실패하면 있던 줄을 두고 오류도 띄우지 않는다', () async {
      repository.rejected = _both;
      await loaded();
      repository.rejected = const FailureResult(NetworkFailure());

      await viewModel().refresh(quiet: true);

      expect(rowIds(), hasLength(2));
      expect(state().error, isNull);
    });

    test('읽는 중에 또 부르면 그 읽기에 합쳐진다', () async {
      repository.holdRejected = Completer<void>();
      viewModel();
      await pumpEventQueue();
      final second = viewModel().refresh(quiet: true);
      repository.holdRejected!.complete();
      await second;

      expect(repository.fetchRejectedCount, 1);
    });
  });

  group('[거절한 카드 다시 보기] 입구 — 7일 안 거절이 있을 때만', () {
    test('읽는 중 · 빈 목록 · 읽기 실패는 숨긴다', () async {
      expect(container.read(hasRejectedCardsProvider), isFalse);
      await pumpEventQueue();
      expect(container.read(hasRejectedCardsProvider), isFalse);

      repository.rejected = const FailureResult(NetworkFailure());
      await viewModel().refresh();
      expect(container.read(hasRejectedCardsProvider), isFalse);
    });

    test('한 줄이라도 있으면 보인다', () async {
      repository.rejected = _both;

      container.read(hasRejectedCardsProvider);
      await pumpEventQueue();

      expect(container.read(hasRejectedCardsProvider), isTrue);
    });
  });

  group('내 카드 다시 신청', () {
    setUp(() => repository.rejected = _both);

    test('성공하면 그 줄을 빼고 목록을 다시 읽고 참을 돌려준다', () async {
      await loaded();
      repository.rejectedAfterWrite = const Success(RejectedCards([_received]));

      final sent = await viewModel().reapply('card-1');

      expect(sent, isTrue);
      expect(repository.reappliedCardIds, ['card-1']);
      expect(repository.fetchRejectedCount, 2);
      expect(rowIds(), ['card-2']);
      expect(state().submittingCardId, isNull);
      expect(state().error, isNull);
    });

    test('다시 읽기 전에 그 줄이 먼저 빠진다 — 보낸 뒤 목록이 늦어도 같은 줄을 또 누르지 않게', () async {
      await loaded();
      repository.holdRejected = Completer<void>();

      final sending = viewModel().reapply('card-1');
      await pumpEventQueue();

      expect(rowIds(), ['card-2']);
      repository.holdRejected!.complete();
      await sending;
    });

    test('[보낸 신청] 탭을 연 적이 있으면 그 목록도 다시 읽는다', () async {
      await loaded();
      await container.read(sentRequestsViewModelProvider.notifier).open();
      expect(repository.fetchSentCount, 1);

      await viewModel().reapply('card-1');
      await pumpEventQueue();

      expect(repository.fetchSentCount, 2);
    });

    test('[보낸 신청] 탭을 연 적이 없으면 보낸 신청은 읽지 않는다(그 탭을 열 때 읽는다)', () async {
      await loaded();

      await viewModel().reapply('card-1');
      await pumpEventQueue();

      expect(repository.fetchSentCount, 0);
    });

    test('404 는 서버 문구를 보이고 그 줄을 빼고 목록을 다시 읽는다', () async {
      await loaded();
      repository.reapplyResult = _cardGone;
      repository.rejectedAfterWrite = const Success(RejectedCards([_received]));

      final sent = await viewModel().reapply('card-1');

      expect(sent, isFalse);
      expect(serverTextOf(state().error), '카드를 찾을 수 없어요');
      expect(state().submittingCardId, isNull);
      expect(rowIds(), ['card-2']);
      expect(repository.fetchRejectedCount, 2);
    });

    test('409 도 서버 문구를 보이고 그 줄을 빼고 목록을 다시 읽는다', () async {
      await loaded();
      repository.reapplyResult = _cardDecided;
      repository.rejectedAfterWrite = const Success(RejectedCards([_received]));

      final sent = await viewModel().reapply('card-1');

      expect(sent, isFalse);
      expect(serverTextOf(state().error), '이미 결정한 카드예요');
      expect(rowIds(), ['card-2']);
      expect(repository.fetchRejectedCount, 2);
    });

    test('서버 문구가 무엇이든 서버 거절이면 같게 다룬다 — 앱은 문구로 가르지 않는다', () async {
      await loaded();
      repository.reapplyResult = const FailureResult(ServerRejectedFailure('바뀐 서버 문구'));

      await viewModel().reapply('card-1');

      expect(serverTextOf(state().error), '바뀐 서버 문구');
      expect(repository.fetchRejectedCount, 2);
    });

    test('다시 읽기가 조용히 실패해도 서버 문구는 남고 그 줄은 빠진 채다', () async {
      await loaded();
      repository.reapplyResult = _cardGone;
      repository.rejectedAfterWrite = const FailureResult(NetworkFailure());

      await viewModel().reapply('card-1');

      expect(serverTextOf(state().error), '카드를 찾을 수 없어요');
      expect(rowIds(), ['card-2']);
    });

    test('그 밖의 실패는 줄을 두고 오류를 올린다 — 목록은 다시 읽지 않는다', () async {
      await loaded();
      repository.reapplyResult = const FailureResult(NetworkFailure());

      final sent = await viewModel().reapply('card-1');

      expect(sent, isFalse);
      expect(state().error, isA<NetworkFailure>());
      expect(state().submittingCardId, isNull);
      expect(rowIds(), ['card-1', 'card-2']);
      expect(repository.fetchRejectedCount, 1);
    });

    test('보내는 중에는 연타해도 서버에 한 번만 간다', () async {
      await loaded();
      repository.holdReapply = Completer<void>();

      final first = viewModel().reapply('card-1');
      await pumpEventQueue();
      expect(state().submittingCardId, 'card-1');
      final second = await viewModel().reapply('card-1');
      repository.holdReapply!.complete();
      await first;

      expect(second, isFalse);
      expect(repository.reappliedCardIds, ['card-1']);
    });

    // 앞 검토 보완 (a): 줄을 빼기 전에 시작한 읽기는 뺀 줄이 든 옛 목록을 돌려준다 — 그 답이 늦게 와서 줄을 되살리면 안 된다.
    test('줄을 빼기 전에 시작한 읽기가 늦게 와도 뺀 줄이 되살아나지 않는다(서버 거절 · 조용한 다시 읽기)', () async {
      await loaded();
      final hold = repository.holdRejected = Completer<void>();
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
      repository.reapplyResult = _cardGone;
      repository.rejectedAfterWrite = const Success(RejectedCards([_received]));

      final sending = viewModel().reapply('card-1');
      await pumpEventQueue();
      hold.complete();
      await sending;
      await pumpEventQueue();

      expect(rowIds(), ['card-2']);
      expect(serverTextOf(state().error), '카드를 찾을 수 없어요');
    });

    test('줄을 빼기 전에 시작한 읽기가 늦게 와도 성공한 줄이 잠깐이라도 되살아나지 않는다', () async {
      await loaded();
      final hold = repository.holdRejected = Completer<void>();
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
      repository.rejectedAfterWrite = const Success(RejectedCards([_received]));
      final seen = <List<String>>[];
      container.listen(
        rejectedCardsViewModelProvider,
        (_, next) => seen.add(next.cards.toList().map((card) => card.cardId).toList()),
      );

      final sending = viewModel().reapply('card-1');
      await pumpEventQueue();
      hold.complete();
      await sending;

      // 처음 빠진 뒤로는 한 번도 다시 보이지 않는다.
      expect(seen.skipWhile((ids) => ids.contains('card-1')).any((ids) => ids.contains('card-1')), isFalse);
      expect(rowIds(), ['card-2']);
    });

    test('보내는 중에 목록 읽기가 끝나도 보내는 중 표시를 지우지 않는다', () async {
      await loaded();
      repository.holdReapply = Completer<void>();

      final sending = viewModel().reapply('card-1');
      await viewModel().refresh(quiet: true);

      expect(state().submittingCardId, 'card-1');
      repository.holdReapply!.complete();
      await sending;
    });
  });

  group('받은 신청 거절 되돌리기', () {
    setUp(() => repository.rejected = _both);

    test('성공하면 매칭 화면으로 보낼 닉네임 · 방을 돌려주고 그 줄을 빼고 다시 읽는다', () async {
      await loaded();
      repository.undoResult = const Success(AcceptanceOutcome(matched: true, matchId: 'match-9'));
      repository.rejectedAfterWrite = const Success(RejectedCards([_mine]));

      final matched = await viewModel().undo('card-2');

      expect(matched, (nickname: '봄비', matchId: 'match-9'));
      expect(repository.undoneCardIds, ['card-2']);
      expect(rowIds(), ['card-1']);
      expect(repository.fetchRejectedCount, 2);
    });

    test('연타 두 번째의 409 는 서버 문구를 보이고 그 줄을 빼고 목록을 다시 읽는다', () async {
      await loaded();
      repository.undoResult = _answered;
      repository.rejectedAfterWrite = const Success(RejectedCards([_mine]));

      final matched = await viewModel().undo('card-2');

      expect(matched, isNull);
      expect(serverTextOf(state().error), '이미 답한 수락이에요');
      expect(rowIds(), ['card-1']);
      expect(repository.fetchRejectedCount, 2);
    });

    // 앞 검토 보완 (b): 되돌리기의 404(없음 · 숨김 · 기한 지남 — 서버가 같은 404 로 묶는다)도 서버 거절이다.
    test('404 는 서버 문구를 보이고 매칭 화면으로 보내지 않으며 그 줄을 빼고 목록을 다시 읽는다', () async {
      await loaded();
      repository.undoResult = const FailureResult(ServerRejectedFailure('받은 신청을 찾을 수 없어요'));
      repository.rejectedAfterWrite = const Success(RejectedCards([_mine]));

      final matched = await viewModel().undo('card-2');

      expect(matched, isNull);
      expect(serverTextOf(state().error), '받은 신청을 찾을 수 없어요');
      expect(state().submittingCardId, isNull);
      expect(rowIds(), ['card-1']);
      expect(repository.fetchRejectedCount, 2);
    });

    test('그 밖의 실패는 오류를 올리고 매칭 화면으로 보내지 않는다', () async {
      await loaded();
      repository.undoResult = const FailureResult(ServerUnavailableFailure());

      final matched = await viewModel().undo('card-2');

      expect(matched, isNull);
      expect(state().error, isA<ServerUnavailableFailure>());
      expect(rowIds(), ['card-1', 'card-2']);
      expect(repository.fetchRejectedCount, 1);
    });

    test('되돌리는 중에는 다른 줄의 다시 신청도 서버에 가지 않는다', () async {
      await loaded();
      repository.holdReapply = Completer<void>();

      final undoing = viewModel().undo('card-2');
      await pumpEventQueue();
      final other = await viewModel().reapply('card-1');
      repository.holdReapply!.complete();
      await undoing;

      expect(other, isFalse);
      expect(repository.reappliedCardIds, isEmpty);
    });
  });

  // §3.1 늦은 응답 — 화면이 닫히거나 로그아웃으로 버려진 뒤 온 답이 ref · state 를 건드리면 던진다.
  group('버려진 뒤 늦은 응답', () {
    ProviderContainer local() => ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(repository)]);

    test('만들자마자 버려지면 읽지 않는다', () async {
      final container = local();
      container.read(rejectedCardsViewModelProvider.notifier);
      container.dispose();
      await pumpEventQueue();

      expect(repository.fetchRejectedCount, 0);
    });

    test('읽는 중에 버려지면 늦게 온 답을 버린다 — 던지지 않는다', () async {
      final container = local();
      final hold = repository.holdRejected = Completer<void>();
      final reading = container.read(rejectedCardsViewModelProvider.notifier).refresh();
      await pumpEventQueue();

      container.dispose();
      hold.complete();

      await expectLater(reading, completes);
    });

    test('조용한 읽기에 조용하지 않은 읽기가 합쳐진 도중 버려지면 다시 읽지 않는다', () async {
      final container = local();
      final hold = repository.holdRejected = Completer<void>();
      final viewModel = container.read(rejectedCardsViewModelProvider.notifier);
      await pumpEventQueue();
      final loud = viewModel.refresh();

      container.dispose();
      hold.complete();

      await expectLater(loud, completes);
      expect(repository.fetchRejectedCount, 1);
    });

    test('다시 신청을 보내는 중에 버려지면 던지지 않고 보낸 신청도 건드리지 않는다', () async {
      repository.rejected = _both;
      final container = local();
      final viewModel = container.read(rejectedCardsViewModelProvider.notifier);
      await pumpEventQueue();
      final hold = repository.holdReapply = Completer<void>();
      final sending = viewModel.reapply('card-1');
      await pumpEventQueue();

      container.dispose();
      hold.complete();

      await expectLater(sending, completion(isTrue));
      expect(repository.fetchRejectedCount, 1);
      expect(repository.fetchSentCount, 0);
    });

    test('되돌리는 중에 버려지면 던지지 않는다', () async {
      repository.rejected = _both;
      final container = local();
      final viewModel = container.read(rejectedCardsViewModelProvider.notifier);
      await pumpEventQueue();
      final hold = repository.holdReapply = Completer<void>();
      final undoing = viewModel.undo('card-2');
      await pumpEventQueue();

      container.dispose();
      hold.complete();

      await expectLater(undoing, completes);
      expect(repository.fetchRejectedCount, 1);
    });
  });
}
