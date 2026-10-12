import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/friend_review/model/friend_review_repository_provider.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_compose_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_compose_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_friend_review_repository.dart';

void main() {
  late FakeFriendReviewRepository repository;
  late ProviderContainer container;

  const revieweeId = 'p2';

  setUp(() {
    repository = FakeFriendReviewRepository();
    container = ProviderContainer(
      overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  FriendReviewComposeViewModel viewModel() =>
      container.read(friendReviewComposeViewModelProvider(revieweeId).notifier);
  FriendReviewComposeUiState state() =>
      container.read(friendReviewComposeViewModelProvider(revieweeId));

  /// autoDispose 라 누군가 보고 있어야 상태가 남는다 — 시트가 떠 있는 동안과 같다.
  /// build() 의 microtask(_load)가 이 호출 전에 미리 돌면 fixture 를 놓치므로,
  /// 이 test 가 repository 값을 다 채운 뒤에 불러야 한다(partner_profile_view_model_test.dart 와 같은 순서).
  Future<void> opened() async {
    container.listen(friendReviewComposeViewModelProvider(revieweeId), (_, _) {});
    await Future<void>.delayed(Duration.zero);
  }

  group('열기', () {
    test('열면 대상을 읽는다', () async {
      repository.target = Success(reviewTargetFixture(profileId: revieweeId, nickname: '달빛'));

      await opened();

      expect(state().isLoading, isFalse);
      expect(state().nickname, '달빛');
      expect(state().alreadyWritten, isFalse);
      expect(repository.targetRequests, [revieweeId]);
    });

    test('여는 중에 시트를 닫아 버려도 응답이 왔을 때 터지지 않는다', () async {
      repository.holdTarget = Completer<void>();
      final sheet = ProviderContainer(
        overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = sheet.listen(friendReviewComposeViewModelProvider(revieweeId), (_, _) {});
      await Future<void>.delayed(Duration.zero);

      // 사용자가 시트를 아래로 밀어 닫았다 — 보던 쪽이 없어져 autoDispose 가 버린다.
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      repository.holdTarget!.complete();

      await Future<void>.delayed(Duration.zero);
      sheet.dispose();
    });

    test('open 이 409 면 alreadyWritten 이고 시트를 띄우지 않을 근거가 된다', () async {
      repository.target = const FailureResult(ServerRejectedFailure('이미 리뷰를 남겼어요'));

      await opened();

      expect(state().alreadyWritten, isTrue);
      expect(state().nickname, isNull);
    });

    test('그 밖의 실패는 loadError 에 담긴다', () async {
      repository.target = const FailureResult(NetworkFailure());

      await opened();

      expect(state().alreadyWritten, isFalse);
      expect(state().loadError, '네트워크 연결을 확인해 주세요');
    });
  });

  group('태그 고르기', () {
    test('태그는 세 개까지 — 네 번째는 무시한다', () async {
      await opened();

      viewModel()
        ..toggleTag('약속을 잘 지켜요')
        ..toggleTag('대화가 편해요')
        ..toggleTag('배려가 깊어요')
        ..toggleTag('유머 감각이 좋아요');

      expect(state().selected, ['약속을 잘 지켜요', '대화가 편해요', '배려가 깊어요']);
    });

    test('고른 태그를 다시 누르면 빠진다', () async {
      await opened();

      viewModel()
        ..toggleTag('약속을 잘 지켜요')
        ..toggleTag('대화가 편해요')
        ..toggleTag('약속을 잘 지켜요');

      expect(state().selected, ['대화가 편해요']);
    });

    test('태그가 없으면 canSubmit 이 false', () async {
      await opened();

      expect(state().canSubmit, isFalse);

      viewModel().toggleTag('약속을 잘 지켜요');

      expect(state().canSubmit, isTrue);
    });

    test('이미 보냈으면 태그가 남아 있어도 canSubmit 이 false', () async {
      await opened();
      viewModel().toggleTag('약속을 잘 지켜요');
      await viewModel().submit();

      expect(state().selected, isNotEmpty);
      expect(state().canSubmit, isFalse);
    });
  });

  group('보내기', () {
    test('submit 은 고른 순서 그대로 태그와 한마디를 보낸다', () async {
      await opened();

      viewModel()
        ..toggleTag('약속을 잘 지켜요')
        ..toggleTag('성실해요')
        ..setComment('믿음직해요');
      await viewModel().submit();

      final sent = repository.creates.single;
      expect(sent.revieweeId, revieweeId);
      expect(sent.tags, ['약속을 잘 지켜요', '성실해요']);
      expect(sent.comment, '믿음직해요');
      expect(state().submitted, isTrue);
      expect(state().isSubmitting, isFalse);
    });

    test('submit 중에 한 번 더 눌러도 한 번만 보낸다', () async {
      await opened();
      repository.holdCreate = Completer<void>();
      viewModel().toggleTag('약속을 잘 지켜요');

      final first = viewModel().submit();
      expect(state().isSubmitting, isTrue);
      expect(state().canSubmit, isFalse);
      await viewModel().submit();

      repository.holdCreate!.complete();
      await first;
      expect(repository.creates, hasLength(1));
    });

    test('보내는 중에 시트를 닫아 버려도 응답이 왔을 때 터지지 않는다', () async {
      repository.holdCreate = Completer<void>();
      final sheet = ProviderContainer(
        overrides: [friendReviewRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = sheet.listen(friendReviewComposeViewModelProvider(revieweeId), (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final notifier = sheet.read(friendReviewComposeViewModelProvider(revieweeId).notifier)
        ..toggleTag('약속을 잘 지켜요');

      final pending = notifier.submit();
      // 사용자가 시트를 아래로 밀어 닫았다 — 보던 쪽이 없어져 autoDispose 가 버린다.
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      repository.holdCreate!.complete();

      await expectLater(pending, completes);
      sheet.dispose();
    });

    test('submit 이 409 면 submitted 가 아니라 submitError', () async {
      await opened();
      repository.createResult = const FailureResult(ServerRejectedFailure('이미 리뷰를 남겼어요'));
      viewModel().toggleTag('약속을 잘 지켜요');

      await viewModel().submit();

      expect(state().submitted, isFalse);
      expect(state().submitError, '이미 리뷰를 남겼어요');
      expect(state().isSubmitting, isFalse);
    });
  });

  group('친구 코드로(20f → 20b)', () {
    final friend = friendCodeMatchFixture(code: 'K7M2QX', nickname: '봄바람');

    FriendReviewComposeViewModel codeViewModel() =>
        container.read(friendCodeReviewComposeViewModelProvider(friend).notifier);
    FriendReviewComposeUiState codeState() => container.read(friendCodeReviewComposeViewModelProvider(friend));

    Future<void> openedByCode() async {
      container.listen(friendCodeReviewComposeViewModelProvider(friend), (_, _) {});
      await Future<void>.delayed(Duration.zero);
    }

    test('열면 대상을 서버에 묻지 않고 확인 결과의 닉네임으로 바로 그린다(프로필 id 가 없다)', () async {
      await openedByCode();

      expect((codeState().isLoading, codeState().nickname, codeState().alreadyWritten), (false, '봄바람', false));
      expect(repository.targetRequests, isEmpty);
    });

    test('submit 은 reviewee_id 가 아니라 friend_code 로 보낸다', () async {
      await openedByCode();
      codeViewModel()
        ..toggleTag('성실해요')
        ..setComment('믿음직해요');

      await codeViewModel().submit();

      final sent = repository.codeCreates.single;
      expect((sent.friendCode, sent.comment), ('K7M2QX', '믿음직해요'));
      expect(sent.tags, ['성실해요']);
      expect(repository.creates, isEmpty);
      expect(codeState().submitted, isTrue);
    });

    test('submit 429 는 서버 문구 "잠시 후 다시 시도해 주세요." 로 보여 준다(앱 기본 한도 문구가 아니라)', () async {
      await openedByCode();
      repository.createResult = const FailureResult(RateLimitedFailure());
      codeViewModel().toggleTag('성실해요');

      await codeViewModel().submit();

      expect((codeState().submitted, codeState().submitError), (false, '잠시 후 다시 시도해 주세요.'));
    });

    for (final detail in ['이미 리뷰를 남겼어요', '코드를 찾을 수 없어요']) {
      test('submit 이 "$detail" 이면 서버 문구 그대로', () async {
        await openedByCode();
        repository.createResult = FailureResult(ServerRejectedFailure(detail));
        codeViewModel().toggleTag('성실해요');

        await codeViewModel().submit();

        expect((codeState().submitted, codeState().submitError), (false, detail));
      });
    }
  });
}
