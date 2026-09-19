import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/auth/model/student_verification_repository_provider.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_ui_state.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_face_detector.dart';
import '../model/fake_image_compressor.dart';
import '../model/fake_student_verification_repository.dart';

void main() {
  late FakeStudentVerificationRepository repository;
  late FakeFaceDetector faceDetector;
  late FakeImageCompressor imageCompressor;
  final photo = File('${Directory.systemTemp.path}/student_id.jpg');

  setUp(() {
    repository = FakeStudentVerificationRepository();
    faceDetector = FakeFaceDetector();
    imageCompressor = FakeImageCompressor();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        studentVerificationRepositoryProvider.overrideWithValue(repository),
        faceDetectorProvider.overrideWithValue(faceDetector),
        imageCompressorProvider.overrideWithValue(imageCompressor),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  StudentVerificationUiState readState(ProviderContainer container) {
    return container.read(studentVerificationViewModelProvider);
  }

  /// 상태 조회가 끝나기를 기다린 뒤 실명·사진까지 채워, 제출할 수 있는 ViewModel 을 만든다.
  /// (조회 응답이 늦게 도착하면 입력을 덮어쓰므로 입력 전에 기다린다)
  Future<StudentVerificationViewModel> buildSubmittableViewModel(ProviderContainer container) async {
    final viewModel = container.read(studentVerificationViewModelProvider.notifier)
      ..pickFromGallery = () async => photo;
    await pumpEventQueue();
    viewModel.changeRealName('홍길동');
    await viewModel.pickPhoto();
    return viewModel;
  }

  test('build() 가 현재 인증 상태를 불러온다', () async {
    repository.nextFetchStatusResult = const Success(VerificationOutcome(status: 'pending'));
    final container = buildContainer();

    expect(readState(container).isLoadingStatus, isTrue);
    await pumpEventQueue();

    expect(readState(container).status, 'pending');
    expect(readState(container).isLoadingStatus, isFalse);
  });

  test('상태 조회가 실패하면 errorMessage 를 남기고 로딩을 끝낸다', () async {
    repository.nextFetchStatusResult = const FailureResult(NetworkFailure());
    final container = buildContainer();

    expect(readState(container).isLoadingStatus, isTrue);
    await pumpEventQueue();

    expect(readState(container).errorMessage, '네트워크 연결을 확인해 주세요');
    expect(readState(container).isLoadingStatus, isFalse);
  });

  test('반려 상태로 돌아오면 반려 사유를 errorMessage 에 담는다', () async {
    repository.nextFetchStatusResult = const Success(
      VerificationOutcome(status: 'rejected', rejectReason: '사진이 흐려요'),
    );
    final container = buildContainer();

    expect(readState(container).isLoadingStatus, isTrue);
    await pumpEventQueue();

    expect(readState(container).status, 'rejected');
    expect(readState(container).errorMessage, '사진이 흐려요');
  });

  test('실명이 형식에 어긋나면 realName 이 다시 비워져 제출할 수 없다', () async {
    final container = buildContainer();
    final viewModel = await buildSubmittableViewModel(container);

    viewModel.changeRealName('   ');

    expect(readState(container).realName, isNull);
    expect(readState(container).selectedPhoto, photo);
    expect(readState(container).canSubmit, isFalse);
  });

  test('얼굴이 검출되지 않으면 서버를 부르지 않고 안내 문구를 남긴다', () async {
    faceDetector.nextResult = false;
    final container = buildContainer();
    final viewModel = await buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(repository.submittedRealNames, isEmpty);
    expect(readState(container).errorMessage, '얼굴이 보이는 사진으로 다시 올려주세요');
    expect(readState(container).isSubmitting, isFalse);
  });

  test('사진을 처리하지 못해 플러그인이 예외를 던져도 제출 중 상태에 갇히지 않는다', () async {
    faceDetector.nextError = Exception('사진을 디코드하지 못했다');
    final container = buildContainer();
    final viewModel = await buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(repository.submittedRealNames, isEmpty);
    expect(readState(container).isSubmitting, isFalse);
    expect(readState(container).errorMessage, isNotNull);
    expect(readState(container).canSubmit, isTrue); // 다시 제출할 수 있어야 한다
  });

  test('원본이 아니라 압축된 사진으로 얼굴을 검출하고 업로드한다', () async {
    final compressed = File('${Directory.systemTemp.path}/student_id_compressed.jpg');
    imageCompressor.nextResult = compressed;
    final container = buildContainer();
    final viewModel = await buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(imageCompressor.compressedSources, [photo]);
    expect(faceDetector.hasFaceCalls, [compressed]);
    expect(repository.submittedPhotos, [compressed]);
  });

  test('제출에 성공하면 status 가 갱신된다', () async {
    repository.nextSubmitResult = const Success(VerificationOutcome(status: 'pending'));
    final container = buildContainer();
    final viewModel = await buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(repository.submittedRealNames, [RealName.tryParse('홍길동')]);
    expect(readState(container).status, 'pending');
    expect(readState(container).isSubmitting, isFalse);
  });

  test('제출에 실패하면 errorMessage 가 채워지고 status 는 그대로다', () async {
    repository.nextSubmitResult = const FailureResult(ServerRejectedFailure('이미 검토 중이에요'));
    final container = buildContainer();
    final viewModel = await buildSubmittableViewModel(container);

    await viewModel.submit();

    expect(readState(container).errorMessage, '이미 검토 중이에요');
    expect(readState(container).status, 'none');
    expect(readState(container).isSubmitting, isFalse);
  });
}
