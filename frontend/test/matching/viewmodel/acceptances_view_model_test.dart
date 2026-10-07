import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/acceptance.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

const _acceptance = Acceptance(
  cardId: 'card-1',
  profile: CardProfile(
    profileId: 'p1',
    nickname: '초코라떼',
    age: 25,
    university: '고려대학교',
    major: '경영학과',
  ),
);

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  test('수락함을 읽어 목록에 담는다', () async {
    repository.acceptances = const Success([_acceptance]);

    await container.read(acceptancesViewModelProvider.notifier).refresh();

    expect(container.read(acceptancesViewModelProvider).acceptances.single.cardId, 'card-1');
  });

  test('수락하면 매칭 결과를 상태에 올린다 — 화면이 12로 넘어갈 재료다', () async {
    repository.acceptances = const Success([_acceptance]);
    repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: true, matchId: 'm-1'));
    final viewModel = container.read(acceptancesViewModelProvider.notifier);
    await viewModel.refresh();
    repository.acceptances = const Success([]);

    await viewModel.respond('card-1', CardDecision.accept);

    final state = container.read(acceptancesViewModelProvider);
    expect(state.matchedNickname, '초코라떼');
    expect(state.acceptances, isEmpty);
  });

  test('거절은 목록에서만 사라지고 매칭 화면으로 가지 않는다', () async {
    repository.acceptances = const Success([_acceptance]);
    final viewModel = container.read(acceptancesViewModelProvider.notifier);
    await viewModel.refresh();
    repository.acceptances = const Success([]);

    await viewModel.respond('card-1', CardDecision.reject);

    final state = container.read(acceptancesViewModelProvider);
    expect(state.matchedNickname, isNull);
    expect(state.acceptances, isEmpty);
  });

  test('기한이 지난 수락(410)은 문구를 보여주고 목록을 다시 읽는다', () async {
    repository.acceptances = const Success([_acceptance]);
    final viewModel = container.read(acceptancesViewModelProvider.notifier);
    await viewModel.refresh();
    repository.acceptanceOutcome = const FailureResult(ServerRejectedFailure('기한이 지났어요'));
    repository.acceptances = const Success([]);

    await viewModel.respond('card-1', CardDecision.accept);

    expect(container.read(acceptancesViewModelProvider).errorMessage, '기한이 지났어요');
    expect(container.read(acceptancesViewModelProvider).acceptances, isEmpty);
  });

  test('12 화면으로 보낸 뒤에는 매칭 상대를 상태에서 지운다', () async {
    repository.acceptances = const Success([_acceptance]);
    repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: true, matchId: 'm-1'));
    final viewModel = container.read(acceptancesViewModelProvider.notifier);
    await viewModel.refresh();
    await viewModel.respond('card-1', CardDecision.accept);

    viewModel.consumeMatched();

    expect(container.read(acceptancesViewModelProvider).matchedNickname, isNull);
  });

  group('조용한 재읽기(앱 복귀·화면 진입)', () {
    AcceptancesViewModel viewModel() => container.read(acceptancesViewModelProvider.notifier);
    AcceptancesUiState stateNow() => container.read(acceptancesViewModelProvider);

    test('실패해도 있던 수락 대기 줄은 남고 오류 문구는 새로 생기지 않는다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.acceptances = const FailureResult(NetworkFailure());

      await viewModel().refresh(quiet: true);

      expect(stateNow().acceptances, hasLength(1));
      expect(stateNow().errorMessage, isNull);
    });

    test('아직 한 번도 못 읽은 상태의 조용한 읽기 실패는 로딩을 끝내고 오류를 보인다', () async {
      repository.acceptances = const FailureResult(NetworkFailure());

      await viewModel().refresh(quiet: true);

      expect(stateNow().isLoading, isFalse);
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
    });

    test('당겨서 새로고침(조용하지 않은 읽기)이 실패하면 오류를 보이고 줄은 남는다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.acceptances = const FailureResult(NetworkFailure());

      await viewModel().refresh();

      expect(stateNow().acceptances, hasLength(1));
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
    });

    test('답을 보내는 중에 조용한 재읽기가 끝나도 보내는 중 표시는 그대로다 — 연타 방지', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.holdRespond = Completer<void>();
      final responding = viewModel().respond('card-1', CardDecision.accept);
      await Future<void>.delayed(Duration.zero);
      expect(stateNow().respondingCardId, 'card-1');

      await viewModel().refresh(quiet: true);

      expect(stateNow().respondingCardId, 'card-1');
      repository.holdRespond!.complete();
      await responding;
      expect(stateNow().respondingCardId, isNull);
    });

    test('답을 보내는 중에 조용하지 않은 읽기가 실패해도 보내는 중 표시는 그대로고 오류를 보인다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.holdRespond = Completer<void>();
      final responding = viewModel().respond('card-1', CardDecision.accept);
      await Future<void>.delayed(Duration.zero);
      repository.acceptances = const FailureResult(NetworkFailure());

      await viewModel().refresh();

      expect(stateNow().respondingCardId, 'card-1');
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
      repository.holdRespond!.complete();
      await responding;
    });

    /// 수락이 성사돼 12 화면으로 보낼 매칭 정보가 상태에 올라간 채로 시작한다.
    Future<void> matchJustMade() async {
      repository.acceptances = const Success([_acceptance]);
      repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: true, matchId: 'm-1'));
      await viewModel().refresh();
      await viewModel().respond('card-1', CardDecision.accept);
      expect(stateNow().matchedNickname, '초코라떼');
    }

    test('조용한 재읽기가 성공해도 방금 성사된 매칭 정보는 지우지 않는다', () async {
      await matchJustMade();
      repository.acceptances = const Success([]);

      await viewModel().refresh(quiet: true);

      expect(stateNow().matchedNickname, '초코라떼');
      expect(stateNow().matchedMatchId, 'm-1');
    });

    test('조용하지 않은 읽기가 실패해도 방금 성사된 매칭 정보는 남고 새 오류 문구가 뜬다', () async {
      await matchJustMade();
      repository.acceptances = const FailureResult(NetworkFailure());

      await viewModel().refresh();

      expect(stateNow().matchedNickname, '초코라떼');
      expect(stateNow().matchedMatchId, 'm-1');
      expect(stateNow().respondingCardId, isNull);
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
    });

    test('조용한 재읽기가 실패해도 방금 성사된 매칭 정보는 지우지 않는다', () async {
      await matchJustMade();
      repository.acceptances = const FailureResult(NetworkFailure());

      await viewModel().refresh(quiet: true);

      expect(stateNow().matchedNickname, '초코라떼');
      expect(stateNow().matchedMatchId, 'm-1');
    });
  });

  group('읽는 중에 겹친 읽기', () {
    AcceptancesViewModel viewModel() => container.read(acceptancesViewModelProvider.notifier);
    AcceptancesUiState stateNow() => container.read(acceptancesViewModelProvider);

    /// 이미 한 줄이 보이는 상태에서, 조용한 읽기가 서버 답을 기다리는 중이다. 이 읽기는 실패로 끝나게 해 둔다.
    Future<void> startQuietReadThatWillFail() async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.holdAcceptances = Completer<void>();
      repository.acceptances = const FailureResult(NetworkFailure());
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
    }

    test('읽는 중에 조용한 호출이 또 와도 서버는 한 번만 읽는다', () async {
      await startQuietReadThatWillFail();
      final before = repository.fetchAcceptancesCount;

      final joined = viewModel().refresh(quiet: true);
      repository.holdAcceptances!.complete();
      await joined;
      await pumpEventQueue();

      expect(repository.fetchAcceptancesCount, before);
    });

    test('당겨서 새로고침이 진행 중인 조용한 읽기에 합쳐진 뒤 실패하면 오류 문구를 보인다', () async {
      await startQuietReadThatWillFail();
      final before = repository.fetchAcceptancesCount;

      final pulled = viewModel().refresh();
      repository.holdAcceptances!.complete();
      await pulled;

      expect(repository.fetchAcceptancesCount, before + 1);
      expect(stateNow().acceptances, hasLength(1));
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
    });

    test('조용하지 않은 호출이 여러 번 합쳐져도 끝난 뒤 다시 읽는 건 한 번이다', () async {
      await startQuietReadThatWillFail();
      final before = repository.fetchAcceptancesCount;

      final first = viewModel().refresh();
      final second = viewModel().refresh();
      repository.holdAcceptances!.complete();
      await Future.wait([first, second]);

      expect(repository.fetchAcceptancesCount, before + 1);
    });

    test('처음 열 때 화면의 조용한 읽기와 뷰모델의 첫 읽기가 합쳐져도 한 번만 읽는다', () async {
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();

      expect(repository.fetchAcceptancesCount, 1);
      expect(stateNow().isLoading, isFalse);
    });

    test('응답 처리 전에 시작된 읽기에 끝의 목록 갱신이 합쳐져도 응답 뒤의 목록을 읽어 온다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      // 서버가 응답을 처리하기 전의 목록(카드가 아직 있다)을 들고 읽는 중이다.
      repository.holdAcceptances = Completer<void>();
      unawaited(viewModel().refresh(quiet: true));
      await pumpEventQueue();
      repository.acceptances = const Success([]);

      final responding = viewModel().respond('card-1', CardDecision.reject);
      await pumpEventQueue();
      repository.holdAcceptances!.complete();
      await responding;

      expect(stateNow().acceptances, isEmpty);
    });
  });

  group('오류 문구', () {
    AcceptancesViewModel viewModel() => container.read(acceptancesViewModelProvider.notifier);
    AcceptancesUiState stateNow() => container.read(acceptancesViewModelProvider);

    test('읽기가 한 번 실패한 뒤 다음 읽기가 성공하면 오류 문구를 지운다', () async {
      repository.acceptances = const FailureResult(NetworkFailure());
      await viewModel().refresh();
      expect(stateNow().errorMessage, isNotNull);
      repository.acceptances = const Success([_acceptance]);

      await viewModel().refresh();

      expect(stateNow().acceptances, hasLength(1));
      expect(stateNow().errorMessage, isNull);
    });

    test('응답이 실패한 뒤 목록 갱신이 성공해도 응답 실패 문구는 남는다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.acceptanceOutcome = const FailureResult(NetworkFailure());

      await viewModel().respond('card-1', CardDecision.accept);

      expect(stateNow().acceptances, hasLength(1));
      expect(stateNow().errorMessage, const NetworkFailure().toDisplayMessage());
      expect(stateNow().respondingCardId, isNull);
    });

    test('응답도 실패하고 목록 갱신(fetchAcceptances)도 실패하면 갱신 실패 문구가 남는다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      // 두 실패의 문구가 달라야 어느 쪽이 남았는지 가려진다(네트워크 vs 서버 일시 불가).
      repository.acceptanceOutcome = const FailureResult(NetworkFailure());
      repository.acceptances = const FailureResult(ServerUnavailableFailure());

      await viewModel().respond('card-1', CardDecision.accept);

      expect(stateNow().errorMessage, const ServerUnavailableFailure().toDisplayMessage());
      expect(stateNow().respondingCardId, isNull);
    });

    test('다음 응답을 보내면 앞의 실패 문구는 지워진다', () async {
      repository.acceptances = const Success([_acceptance]);
      await viewModel().refresh();
      repository.acceptanceOutcome = const FailureResult(NetworkFailure());
      await viewModel().respond('card-1', CardDecision.accept);
      repository.acceptanceOutcome = const Success(AcceptanceOutcome(matched: false));

      await viewModel().respond('card-1', CardDecision.accept);

      expect(stateNow().errorMessage, isNull);
    });
  });
}
