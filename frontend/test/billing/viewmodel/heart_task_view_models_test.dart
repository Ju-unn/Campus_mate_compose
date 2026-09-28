import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_heart_task_repository.dart';

void main() {
  late FakeHeartTaskRepository repository;
  late FakeImageCompressor compressor;
  late ProviderContainer container;
  final photo = File('picked.jpg');

  setUp(() {
    repository = FakeHeartTaskRepository();
    compressor = FakeImageCompressor();
    container = ProviderContainer(overrides: [
      heartTaskRepositoryProvider.overrideWithValue(repository),
      imageCompressorProvider.overrideWithValue(compressor),
    ]);
    addTearDown(container.dispose);
  });

  /// autoDispose 라 듣는 쪽이 있어야 살아 있다. 갤러리는 늘 [photo] 를 고른 것으로 한다.
  HeartTaskSubmitViewModel submitViewModel() {
    container.listen(heartTaskSubmitViewModelProvider, (_, _) {});
    return container.read(heartTaskSubmitViewModelProvider.notifier)..pickFromGallery = () async => photo;
  }

  test('18a 는 처음 불러오는 중이고, 읽으면 서버 세 줄이다', () async {
    container.listen(heartTasksViewModelProvider, (_, _) {});
    expect(container.read(heartTasksViewModelProvider).isLoading, isTrue);

    await pumpEventQueue();

    final state = container.read(heartTasksViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.tasks.map((task) => task.kind), HeartTaskKind.values);
  });

  test('18a 읽기가 실패하면 문구를 둔다', () async {
    repository.tasks = const FailureResult(NetworkFailure());
    container.listen(heartTasksViewModelProvider, (_, _) {});

    await pumpEventQueue();

    expect(container.read(heartTasksViewModelProvider).errorMessage, '네트워크 연결을 확인해 주세요');
  });

  test('사진을 고르지 않고 닫으면 아무것도 바뀌지 않는다', () async {
    final viewModel = submitViewModel()..pickFromGallery = () async => null;

    await viewModel.pickPhoto();

    expect(container.read(heartTaskSubmitViewModelProvider).photo, isNull);
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isFalse);
  });

  test('제출이 성공하면 압축본을 올리고 submitted 가 되며 18a 목록을 다시 읽는다', () async {
    container.listen(heartTasksViewModelProvider, (_, _) {});
    await pumpEventQueue();
    compressor.nextResult = File('compressed.jpg');
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isTrue);
    await viewModel.submit(HeartTaskKind.everytimePost);
    await pumpEventQueue();

    expect(compressor.compressedSources, [photo]);
    expect(repository.submitted, [(HeartTaskKind.everytimePost, 'compressed.jpg')]);
    expect(container.read(heartTaskSubmitViewModelProvider).submitted, isTrue);
    expect(repository.fetchCount, 2);
  });

  test('월 한도 429 는 공용 문구가 아니라 월 한도 문구다', () async {
    repository.submitResult = const FailureResult(RateLimitedFailure());
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    final state = container.read(heartTaskSubmitViewModelProvider);
    expect(state.errorMessage, heartTaskMonthlyLimitMessage);
    expect(state.submitted, isFalse);
    expect(state.photo, photo);
  });

  test('검수 중 409 는 서버 문구 그대로고, 18a 목록도 다시 읽는다', () async {
    repository.submitResult = const FailureResult(ServerRejectedFailure('이미 확인 중이에요, 결과를 기다려 주세요'));
    container.listen(heartTasksViewModelProvider, (_, _) {});
    await pumpEventQueue();
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    await viewModel.submit(HeartTaskKind.kakaoShare);
    await pumpEventQueue();

    expect(container.read(heartTaskSubmitViewModelProvider).errorMessage, '이미 확인 중이에요, 결과를 기다려 주세요');
    // 다른 기기가 먼저 냈거나 응답만 끊겼다 — 18a 로 돌아가면 "검수중" 이 보여야 한다.
    expect(repository.fetchCount, 2);
  });

  test('압축이 사진을 못 읽으면 올리지 않고 사진 문구를 둔다', () async {
    compressor.nextError = Exception('unreadable');
    final viewModel = submitViewModel();

    await viewModel.pickPhoto();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    expect(repository.submitted, isEmpty);
    expect(container.read(heartTaskSubmitViewModelProvider).errorMessage, heartTaskPhotoUnreadableMessage);
  });

  test('보내는 중에 한 번 더 눌러도 한 번만 올린다', () async {
    repository.holdSubmit = Completer<void>();
    final viewModel = submitViewModel();
    await viewModel.pickPhoto();

    final first = viewModel.submit(HeartTaskKind.kakaoShare);
    await pumpEventQueue();
    expect(container.read(heartTaskSubmitViewModelProvider).isSubmitting, isTrue);
    // 두 번째를 await 하지 않는다 — 막기가 빠지면 시간 초과가 아니라 아래 단정(2번)으로 떨어지게.
    final second = viewModel.submit(HeartTaskKind.kakaoShare);
    repository.holdSubmit!.complete();
    await Future.wait([first, second]);

    expect(repository.submitted, hasLength(1));
  });
}
