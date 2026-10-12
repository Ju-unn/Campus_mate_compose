import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_code_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_code_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_friend_review_repository.dart';

/// 20f 친구 코드로 리뷰 쓰기(pen eShpy · a6jyqI · Q3xfwm · uovMC · Mi3ux)의 흐름.
void main() {
  late FakeFriendReviewRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeFriendReviewRepository();
    container = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    // autoDispose 라 화면이 떠 있는 동안처럼 누군가 보고 있어야 한다.
    container.listen(friendCodeViewModelProvider, (_, _) {});
  });

  FriendCodeViewModel viewModel() => container.read(friendCodeViewModelProvider.notifier);
  FriendCodeUiState state() => container.read(friendCodeViewModelProvider);

  test('처음은 입력 전(20f-1) — 코드가 비어 확인할 수 없다', () {
    expect((state().phase, state().code, state().canCheck, state().friend), (FriendCodePhase.input, '', false, null));
  });

  test('코드를 넣으면 확인할 수 있다', () {
    viewModel().changeCode('K7M2QX');

    expect((state().code, state().canCheck), ('K7M2QX', true));
  });

  test('코드가 6자(referralCodeLength)가 아니면 확인할 수 없다 — 20 화면과 같다', () {
    viewModel().changeCode('K7M2Q');

    expect(state().canCheck, isFalse);
  });

  test('확인 중에는 다시 확인하지 않는다 — 한 번만 보낸다', () async {
    repository.holdLookup = Completer<void>();
    viewModel().changeCode('K7M2QX');

    final first = viewModel().check();
    expect((state().phase, state().canCheck), (FriendCodePhase.checking, false));
    await viewModel().check();
    repository.holdLookup!.complete();
    await first;

    expect(repository.lookups, ['K7M2QX']);
  });

  test('맞으면 확인 성공(20f-3) — 닉네임 · 학교, 쓸 수 있다', () async {
    repository.lookupResult = Success(friendCodeMatchFixture(nickname: '봄바람', university: '테스트대학교'));
    viewModel().changeCode('K7M2QX');

    await viewModel().check();

    expect(state().phase, FriendCodePhase.found);
    expect((state().friend?.nickname, state().friend?.university, state().canWrite), ('봄바람', '테스트대학교', true));
  });

  test('already_reviewed 면 이미 쓴 친구(20f-3b) — 친구는 보이고 쓸 수 없다', () async {
    repository.lookupResult = Success(friendCodeMatchFixture(alreadyReviewed: true));
    viewModel().changeCode('K7M2QX');

    await viewModel().check();

    expect((state().phase, state().friend?.nickname, state().canWrite), (FriendCodePhase.alreadyReviewed, '봄바람', false));
  });

  test('404 "코드를 찾을 수 없어요" 면 오류(20f-2) — 고쳐서 다시 확인할 수 있다', () async {
    repository.lookupResult = const FailureResult(ServerRejectedFailure('코드를 찾을 수 없어요'));
    viewModel().changeCode('ZZZZZZ');

    await viewModel().check();

    expect((state().phase, state().friend, state().canCheck), (FriendCodePhase.notFound, null, true));
  });

  test('429 면 횟수 제한(20f-4) — 코드를 고치기 전까지 확인 버튼이 꺼진다', () async {
    repository.lookupResult = const FailureResult(RateLimitedFailure());
    viewModel().changeCode('K7M2QX');

    await viewModel().check();

    expect((state().phase, state().canCheck), (FriendCodePhase.tryLater, false));
    viewModel().changeCode('A1B2C3');
    expect((state().phase, state().canCheck), (FriendCodePhase.input, true));
  });

  test('그 밖의 실패(네트워크 등)는 문구를 담고 다시 확인할 수 있다', () async {
    repository.lookupResult = const FailureResult(NetworkFailure());
    viewModel().changeCode('K7M2QX');

    await viewModel().check();

    expect((state().phase, state().failureMessage, state().canCheck), (FriendCodePhase.failed, '네트워크 연결을 확인해 주세요', true));
  });

  test('확인 뒤 코드를 고치면 입력 전으로 — 친구 · 오류가 지워진다', () async {
    viewModel().changeCode('K7M2QX');
    await viewModel().check();

    viewModel().changeCode('K7M2QA');

    expect((state().phase, state().friend, state().code), (FriendCodePhase.input, null, 'K7M2QA'));
  });

  test('같은 코드가 다시 들어와도(포매터가 같은 글을 다시 줄 때) 결과를 지우지 않는다', () async {
    viewModel().changeCode('K7M2QX');
    await viewModel().check();

    viewModel().changeCode('K7M2QX');

    expect(state().phase, FriendCodePhase.found);
  });

  test('확인 중에 코드를 고치면 늦게 온 답은 버린다 — 고친 코드로 성공처럼 보이지 않게', () async {
    repository.holdLookup = Completer<void>();
    viewModel().changeCode('K7M2QX');
    final pending = viewModel().check();

    viewModel().changeCode('A1B2C3');
    repository.holdLookup!.complete();
    await pending;

    expect((state().phase, state().code, state().friend), (FriendCodePhase.input, 'A1B2C3', null));
  });

  test('20b 에서 남기고 오면 markReviewed — 이미 쓴 친구로 바뀌어 다시 쓰지 않는다', () async {
    viewModel().changeCode('K7M2QX');
    await viewModel().check();

    viewModel().markReviewed();

    expect((state().phase, state().friend?.alreadyReviewed, state().canWrite), (FriendCodePhase.alreadyReviewed, true, false));
  });

  test('20b 를 남기지 않고 닫으면 recheck — 그새 썼으면(409 · 닫는 사이 저장) 이미 쓴 친구', () async {
    viewModel().changeCode('K7M2QX');
    await viewModel().check();
    repository.lookupResult = Success(friendCodeMatchFixture(alreadyReviewed: true));

    await viewModel().recheck();

    expect((state().phase, state().canWrite), (FriendCodePhase.alreadyReviewed, false));
    expect(repository.lookups, ['K7M2QX', 'K7M2QX']);
  });

  for (final failure in const <Failure>[ServerRejectedFailure('코드를 찾을 수 없어요'), RateLimitedFailure(), NetworkFailure()]) {
    test('recheck 가 실패(${failure.runtimeType})면 확인 성공 그대로 — 친구 줄을 지우지 않는다', () async {
      viewModel().changeCode('K7M2QX');
      await viewModel().check();
      repository.lookupResult = FailureResult(failure);

      await viewModel().recheck();

      expect((state().phase, state().friend?.nickname), (FriendCodePhase.found, '봄바람'));
    });
  }

  test('확인 성공이 아니면 recheck 는 묻지 않는다', () async {
    viewModel().changeCode('K7M2QX');

    await viewModel().recheck();

    expect(repository.lookups, isEmpty);
  });

  test('확인 중에 화면을 나가도 늦게 온 답에 터지지 않는다', () async {
    repository.holdLookup = Completer<void>();
    final screen = ProviderContainer(overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)]);
    final subscription = screen.listen(friendCodeViewModelProvider, (_, _) {});
    final notifier = screen.read(friendCodeViewModelProvider.notifier)..changeCode('K7M2QX');
    final pending = notifier.check();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    repository.holdLookup!.complete();

    await expectLater(pending, completes);
    screen.dispose();
  });
}
