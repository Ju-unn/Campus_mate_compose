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

  group('refresh(20c · 20e 에 들어올 때)', () {
    const args = (source: FriendReviewListSource.received, profileId: null);

    test('처음 읽는 중이면 또 보내지 않는다', () async {
      container.listen(friendReviewListViewModelProvider(args), (_, _) {});
      await container.read(friendReviewListViewModelProvider(args).notifier).refresh();
      await settled();

      expect(repository.receivedCount, 1);
    });

    test('읽은 뒤면 다시 읽어 늘어난 리뷰를 받는다', () async {
      repository.received = Success([friendReviewFixture(id: 'r1')]);
      container.listen(friendReviewListViewModelProvider(args), (_, _) {});
      await settled();
      repository.received = Success([friendReviewFixture(id: 'r0'), friendReviewFixture(id: 'r1')]);

      await container.read(friendReviewListViewModelProvider(args).notifier).refresh();

      expect(repository.receivedCount, 2);
      expect(container.read(friendReviewListViewModelProvider(args)).reviews, hasLength(2));
    });

    test('다시 읽다 실패하면 보던 목록을 그대로 둔다', () async {
      repository.received = Success([friendReviewFixture(id: 'r1')]);
      container.listen(friendReviewListViewModelProvider(args), (_, _) {});
      await settled();
      repository.received = const FailureResult(NetworkFailure());

      await container.read(friendReviewListViewModelProvider(args).notifier).refresh();

      final state = container.read(friendReviewListViewModelProvider(args));
      expect(state.reviews, hasLength(1));
      expect(state.errorMessage, isNull);
    });
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

  group('written(20e) · delete', () {
    const args = (source: FriendReviewListSource.written, profileId: null);

    Future<FriendReviewListViewModel> loaded() async {
      repository.written = Success([friendReviewFixture(id: 'r1'), friendReviewFixture(id: 'r2', nickname: '봄바람')]);
      container.listen(friendReviewListViewModelProvider(args), (_, _) {});
      await settled();
      return container.read(friendReviewListViewModelProvider(args).notifier);
    }

    List<String> ids() => [for (final review in container.read(friendReviewListViewModelProvider(args)).reviews) review.id];

    test('written 은 fetchWritten 을 부른다', () async {
      await loaded();

      expect(repository.writtenCount, 1);
      expect(repository.receivedCount, 0);
      expect(ids(), ['r1', 'r2']);
    });

    test('지우기에 성공하면 그 리뷰만 목록에서 빼고 null 을 돌려준다', () async {
      final viewModel = await loaded();

      expect(await viewModel.delete('r2'), isNull);

      expect(repository.deletes, ['r2']);
      expect(ids(), ['r1']);
    });

    test('다시 읽는 중에 지우면 늦게 온 옛 목록이 지운 리뷰를 되살리지 않는다(재검토 권고 1)', () async {
      final viewModel = await loaded();
      repository.holdWritten = Completer<void>();
      final refreshing = viewModel.refresh();

      expect(await viewModel.delete('r2'), isNull);
      repository.holdWritten!.complete();
      await refreshing;

      expect(ids(), ['r1']);
    });

    test('실패하면 문구를 돌려주고 목록은 그대로 둔다', () async {
      final viewModel = await loaded();
      repository.deleteResult = const FailureResult(NetworkFailure());

      expect(await viewModel.delete('r2'), '네트워크 연결을 확인해 주세요');

      expect(ids(), ['r1', 'r2']);
    });

    test('그새 없어진 리뷰(404)면 서버 문구를 돌려주고 목록에서도 뺀다 — 남겨 두면 다시 눌러도 404 뿐이다', () async {
      final viewModel = await loaded();
      repository.deleteResult = const FailureResult(ServerRejectedFailure('리뷰를 찾을 수 없어요'));

      expect(await viewModel.delete('r2'), '리뷰를 찾을 수 없어요');

      expect(ids(), ['r1']);
    });

    test('같은 리뷰를 지우는 중에 또 부르면 요청은 한 번이고 둘 다 같은 결과를 받는다', () async {
      final viewModel = await loaded();
      repository.holdDelete = Completer<void>();

      final first = viewModel.delete('r2');
      final second = viewModel.delete('r2');
      repository.holdDelete!.complete();

      expect(await Future.wait([first, second]), [null, null]);
      expect(repository.deletes, ['r2']);
      // 끝난 뒤 다시 부르면(다른 기회) 새로 보낸다.
      await viewModel.delete('r2');
      expect(repository.deletes, ['r2', 'r2']);
    });
  });
}
