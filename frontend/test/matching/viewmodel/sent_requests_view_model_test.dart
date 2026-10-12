import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/sent_request.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

const _waiting = SentRequest(
  cardId: 'card-1',
  status: SentRequestStatus.waiting,
  daysLeft: 3,
  profile: CardProfile(nickname: '여우비', age: 23),
);

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(overrides: [cardRepositoryProvider.overrideWithValue(repository)]);
  });

  tearDown(() => container.dispose());

  SentRequestsViewModel viewModel() => container.read(sentRequestsViewModelProvider.notifier);

  test('처음에는 읽는 중이고, 읽으면 서버 목록을 그대로 담는다', () async {
    repository.sent = const Success([_waiting]);

    expect(container.read(sentRequestsViewModelProvider).isLoading, isTrue);
    await viewModel().refresh();

    final state = container.read(sentRequestsViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.requests.single.cardId, 'card-1');
    expect(state.errorMessage, isNull);
  });

  test('보낸 신청이 없으면 빈 목록이다', () async {
    await viewModel().refresh();

    final state = container.read(sentRequestsViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.requests, isEmpty);
  });

  test('처음 읽기가 실패하면 조용히 불렸어도 로딩을 끝내고 오류를 보인다', () async {
    repository.sent = const FailureResult(NetworkFailure());

    await viewModel().refresh(quiet: true);

    final state = container.read(sentRequestsViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('조용한 다시 읽기가 실패하면 있던 줄을 두고 오류도 띄우지 않는다', () async {
    repository.sent = const Success([_waiting]);
    await viewModel().refresh();
    repository.sent = const FailureResult(NetworkFailure());

    await viewModel().refresh(quiet: true);

    final state = container.read(sentRequestsViewModelProvider);
    expect(state.requests, hasLength(1));
    expect(state.errorMessage, isNull);
  });

  test('당겨서 새로고침이 실패하면 줄은 두고 오류를 보인다', () async {
    repository.sent = const Success([_waiting]);
    await viewModel().refresh();
    repository.sent = const FailureResult(NetworkFailure());

    await viewModel().refresh();

    final state = container.read(sentRequestsViewModelProvider);
    expect(state.requests, hasLength(1));
    expect(state.errorMessage, isNotNull);
  });

  test('읽는 중에 또 부르면 그 읽기에 합쳐진다', () async {
    repository.holdSent = Completer<void>();
    final first = viewModel().refresh(quiet: true);
    final second = viewModel().refresh(quiet: true);
    await pumpEventQueue();
    repository.holdSent!.complete();
    await Future.wait([first, second]);

    expect(repository.fetchSentCount, 1);
  });

  test('대화 신청을 보낸 직후에는 처음처럼 다시 읽고, 대화 탭이 그 사실을 한 번만 꺼내 간다', () async {
    await viewModel().refresh();
    repository.sent = const Success([_waiting]);

    final reading = viewModel().announceSent();
    // 새 줄이 빠진 옛 목록을 그리지 않게 읽는 동안은 로딩이다.
    expect(container.read(sentRequestsViewModelProvider).isLoading, isTrue);
    await reading;

    expect(container.read(sentRequestsViewModelProvider).requests.single.cardId, 'card-1');
    expect(viewModel().takeJustSent(), isTrue);
    expect(viewModel().takeJustSent(), isFalse);
  });

  test('대화 신청 직전에 시작한 옛 읽기 결과는 버리고 로딩 뒤 새 목록만 그린다', () async {
    // 옛 읽기가 새 줄이 빠진 빈 목록을 쥔 채 멈춰 있다.
    repository.holdSent = Completer<void>();
    final states = <SentRequestsUiState>[];
    container.listen(sentRequestsViewModelProvider, (_, next) => states.add(next), fireImmediately: true);
    final older = viewModel().refresh(quiet: true);
    await pumpEventQueue();

    repository.sent = const Success([_waiting]);
    final reading = viewModel().announceSent();
    repository.holdSent!.complete();
    await Future.wait([older, reading]);

    // 로딩이 끝난 채 빈 목록이 그려진 적이 없어야 한다(옛 읽기가 먼저 그려지면 새 줄이 끼어든다).
    expect(states.any((s) => !s.isLoading && s.requests.isEmpty && s.errorMessage == null), isFalse);
    expect(container.read(sentRequestsViewModelProvider).requests.single.cardId, 'card-1');
  });

  test('신청을 보내지 않았으면 대화 탭이 꺼내 갈 것이 없다', () {
    expect(viewModel().takeJustSent(), isFalse);
  });
}
