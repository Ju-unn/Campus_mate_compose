import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_friend_review_repository.dart';

void main() {
  late FakeFriendReviewRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeFriendReviewRepository();
    container = ProviderContainer(
      overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  Future<void> settled() => Future<void>.delayed(Duration.zero);

  test('about 는 fetchAbout(profileId) 를 부른다', () async {
    repository.about = Success([friendReviewFixture(id: 'r1')]);
    const args = (source: FriendReviewListSource.about, profileId: 'p2');
    container.listen(friendReviewListViewModelProvider(args), (_, _) {});

    await settled();

    final state = container.read(friendReviewListViewModelProvider(args));
    expect(repository.aboutRequests, ['p2']);
    expect(repository.receivedCount, 0);
    expect(state.isLoading, isFalse);
    expect(state.reviews, hasLength(1));
    expect(state.errorMessage, isNull);
  });

  test('received 는 fetchReceived 를 부른다', () async {
    repository.received = Success([friendReviewFixture(id: 'r2')]);
    const args = (source: FriendReviewListSource.received, profileId: null);
    container.listen(friendReviewListViewModelProvider(args), (_, _) {});

    await settled();

    final state = container.read(friendReviewListViewModelProvider(args));
    expect(repository.receivedCount, 1);
    expect(repository.aboutRequests, isEmpty);
    expect(state.reviews, hasLength(1));
  });

  test('실패하면 errorMessage 에 담긴다', () async {
    repository.received = const FailureResult(NetworkFailure());
    const args = (source: FriendReviewListSource.received, profileId: null);
    container.listen(friendReviewListViewModelProvider(args), (_, _) {});

    await settled();

    final state = container.read(friendReviewListViewModelProvider(args));
    expect(state.isLoading, isFalse);
    expect(state.reviews, isEmpty);
    expect(state.errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('읽는 중에 화면을 떠나도 응답이 왔을 때 터지지 않는다', () async {
    repository.holdReceived = Completer<void>();
    const args = (source: FriendReviewListSource.received, profileId: null);
    final subscription = container.listen(friendReviewListViewModelProvider(args), (_, _) {});
    await Future<void>.delayed(Duration.zero);

    // 목록 화면을 뒤로가기로 닫았다 — 보던 쪽이 없어져 autoDispose 가 버린다.
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    repository.holdReceived!.complete();

    await Future<void>.delayed(Duration.zero);
  });
}
