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

  /// autoDispose 라 듣는 쪽이 있어야 살아 있다. 갤러리는 늘 [photo] 한 장을 고른 것으로 한다.
  HeartTaskSubmitViewModel submitViewModel() {
    container.listen(heartTaskSubmitViewModelProvider, (_, _) {});
    return container.read(heartTaskSubmitViewModelProvider.notifier)..pickFromGallery = (remaining) async => [photo];
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
    final viewModel = submitViewModel()..pickFromGallery = (remaining) async => [];

    await viewModel.addPhotos();

    expect(container.read(heartTaskSubmitViewModelProvider).photos, isEmpty);
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isFalse);
  });

  test('사진은 고른 순서대로 쌓이고 세 장에서 멈춘다 — 남은 자리만큼만 갤러리에 청한다', () async {
    final asked = <int>[];
    final batches = [
      [File('a.jpg'), File('b.jpg')],
      [File('c.jpg'), File('d.jpg')], // 한 자리만 남았는데 둘을 돌려주는 갤러리 — 앞 한 장만 받는다
    ];
    final viewModel = submitViewModel()
      ..pickFromGallery = (remaining) async {
        asked.add(remaining);
        return batches.removeAt(0);
      };

    await viewModel.addPhotos();
    await viewModel.addPhotos();
    await viewModel.addPhotos(); // 이미 세 장 — 갤러리를 부르지 않는다

    expect(asked, [3, 1]);
    expect(container.read(heartTaskSubmitViewModelProvider).photos.map((file) => file.path), ['a.jpg', 'b.jpg', 'c.jpg']);
  });

  test('removePhoto 는 그 사진만 빼고, 다 빼면 낼 수 없다', () async {
    final viewModel = submitViewModel()
      ..pickFromGallery = (remaining) async => [File('a.jpg'), File('b.jpg')];
    await viewModel.addPhotos();

    viewModel.removePhoto(0);
    expect(container.read(heartTaskSubmitViewModelProvider).photos.map((file) => file.path), ['b.jpg']);
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isTrue);
    viewModel.removePhoto(0);
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isFalse);
    viewModel.removePhoto(5); // 없는 자리는 무시한다
  });

  test('옛 서버(max_photos 1)면 한 장에서 멈춘다 — maxPhotos 를 항목 값으로 넘긴다', () async {
    final asked = <int>[];
    final viewModel = submitViewModel()
      ..pickFromGallery = (remaining) async {
        asked.add(remaining);
        return [File('a.jpg'), File('b.jpg')];
      };

    await viewModel.addPhotos(maxPhotos: 1);
    await viewModel.addPhotos(maxPhotos: 1);

    expect(asked, [1]);
    expect(container.read(heartTaskSubmitViewModelProvider).photos.map((file) => file.path), ['a.jpg']);
  });

  test('세 장을 모두 압축해 한 번에 올리고, 압축본을 전부 지운다', () async {
    final sources = [File('a.jpg'), File('b.jpg'), File('c.jpg')];
    final viewModel = submitViewModel()..pickFromGallery = (remaining) async => sources;
    await viewModel.addPhotos();

    await viewModel.submit(HeartTaskKind.kakaoShare);
    await pumpEventQueue(); // 압축본 지우기는 기다리지 않고 흘려보낸다

    expect(compressor.compressedSources, sources);
    expect(repository.submitted, [(HeartTaskKind.kakaoShare, 'a.jpg,b.jpg,c.jpg')]);
    expect(compressor.discardedPaths, ['a.jpg', 'b.jpg', 'c.jpg']);
    expect(container.read(heartTaskSubmitViewModelProvider).submitted, isTrue);
  });

  test('어느 한 장이라도 압축이 안 되면 아무것도 올리지 않고, 이미 만든 압축본은 지운다', () async {
    final sources = [File('a.jpg'), File('b.jpg')];
    final viewModel = submitViewModel()..pickFromGallery = (remaining) async => sources;
    await viewModel.addPhotos();
    compressor.failOnCall = 2;

    await viewModel.submit(HeartTaskKind.kakaoShare);

    expect(repository.submitted, isEmpty);
    expect(compressor.discardedPaths, ['a.jpg']);
    final state = container.read(heartTaskSubmitViewModelProvider);
    expect(state.errorMessage, heartTaskPhotoUnreadableMessage);
    expect(state.photos.length, 2); // 고른 사진은 남아 다시 누를 수 있다
  });

  test('제출이 성공하면 압축본을 올리고 submitted 가 되며 18a 목록을 다시 읽는다', () async {
    container.listen(heartTasksViewModelProvider, (_, _) {});
    await pumpEventQueue();
    compressor.nextResult = File('compressed.jpg');
    final viewModel = submitViewModel();

    await viewModel.addPhotos();
    expect(container.read(heartTaskSubmitViewModelProvider).canSubmit, isTrue);
    await viewModel.submit(HeartTaskKind.everytimePost);
    await pumpEventQueue();

    expect(compressor.compressedSources, [photo]);
    expect(repository.submitted, [(HeartTaskKind.everytimePost, 'compressed.jpg')]);
    expect(container.read(heartTaskSubmitViewModelProvider).submitted, isTrue);
    expect(repository.fetchCount, 2);
  });

  // 압축본(인증샷 사본)을 폰에 남기지 않는다(2026-10-18 보안 검사). 다시 보낼 때는 고른 사진에서 다시 압축한다.
  for (final (name, failure) in <(String, Failure?)>[
    ('올리기에 성공하면', null),
    ('올리기가 막혀도', const NetworkFailure()),
  ]) {
    test('$name 압축본을 지운다', () async {
      if (failure != null) repository.submitResult = FailureResult(failure);
      compressor.nextResult = File('compressed.jpg');
      final viewModel = submitViewModel();

      await viewModel.addPhotos();
      await viewModel.submit(HeartTaskKind.everytimePost);

      expect(compressor.discardedPaths, ['compressed.jpg']);
    });
  }

  test('월 한도 429 는 공용 문구가 아니라 월 한도 문구다', () async {
    repository.submitResult = const FailureResult(RateLimitedFailure());
    final viewModel = submitViewModel();

    await viewModel.addPhotos();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    final state = container.read(heartTaskSubmitViewModelProvider);
    expect(state.errorMessage, heartTaskMonthlyLimitMessage);
    expect(state.submitted, isFalse);
    expect(state.photos, [photo]);
  });

  test('검수 중 409 는 서버 문구 그대로고, 18a 목록도 다시 읽는다', () async {
    repository.submitResult = const FailureResult(ServerRejectedFailure('이미 확인 중이에요, 결과를 기다려 주세요'));
    container.listen(heartTasksViewModelProvider, (_, _) {});
    await pumpEventQueue();
    final viewModel = submitViewModel();

    await viewModel.addPhotos();
    await viewModel.submit(HeartTaskKind.kakaoShare);
    await pumpEventQueue();

    expect(container.read(heartTaskSubmitViewModelProvider).errorMessage, '이미 확인 중이에요, 결과를 기다려 주세요');
    // 다른 기기가 먼저 냈거나 응답만 끊겼다 — 18a 로 돌아가면 "검수중" 이 보여야 한다.
    expect(repository.fetchCount, 2);
  });

  test('압축이 사진을 못 읽으면 올리지 않고 사진 문구를 둔다', () async {
    compressor.nextError = Exception('unreadable');
    final viewModel = submitViewModel();

    await viewModel.addPhotos();
    await viewModel.submit(HeartTaskKind.kakaoShare);

    expect(repository.submitted, isEmpty);
    expect(container.read(heartTaskSubmitViewModelProvider).errorMessage, heartTaskPhotoUnreadableMessage);
  });

  test('보내는 중에 한 번 더 눌러도 한 번만 올린다', () async {
    repository.holdSubmit = Completer<void>();
    final viewModel = submitViewModel();
    await viewModel.addPhotos();

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
