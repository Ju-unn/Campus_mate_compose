import 'dart:io';

import 'package:campus_mate/auth/model/face_detector_provider.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/auth/model/student_verification_repository_provider.dart';
import 'package:campus_mate/auth/viewmodel/student_verification_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final studentVerificationViewModelProvider =
    NotifierProvider<StudentVerificationViewModel, StudentVerificationUiState>(
  StudentVerificationViewModel.new,
);

/// 서버가 돌려주는 '반려' 상태 값. 이때만 반려 사유를 문구로 함께 보여준다.
const String _rejectedStatus = 'rejected';

/// `_copyWith` 에서 "이 필드는 건드리지 않는다" 를 뜻하는 표식.
/// 넘기지 않은 것과 `null` 을 넘겨 값을 지우는 것을 구분하기 위해 필요하다
/// (실명이 형식에 어긋나면 `realName` 을 다시 `null` 로 지워야 한다).
const Object _keep = Object();

/// 갤러리에서 학생증 사진 한 장을 고른다.
/// image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어
/// [StudentVerificationViewModel.pickFromGallery] 훅으로 갈아끼운다.
Future<File?> _pickFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked == null ? null : File(picked.path);
}

/// 학생증 인증 화면(DESIGN.md 화면 3b)의 흐름을 맡는다.
class StudentVerificationViewModel extends Notifier<StudentVerificationUiState> {
  /// 테스트에서 갤러리 호출을 대체하기 위한 훅. 기본은 실제 image_picker.
  Future<File?> Function() pickFromGallery = _pickFromGallery;

  @override
  StudentVerificationUiState build() {
    // build() 는 동기라서 상태 조회는 마이크로태스크로 띄운다.
    // 앱을 나갔다 돌아온 pending 사용자에게 검토 중 화면을 바로 보여주기 위함이다.
    Future.microtask(refreshStatus);
    return const StudentVerificationUiState();
  }

  /// 인증 상태를 서버에 다시 물어본다.
  /// 화면을 열 때 한 번, 그리고 대기 중이면 화면이 30초마다 다시 부른다(Task A11 폴링).
  Future<void> refreshStatus() async {
    final result = await ref.read(studentVerificationRepositoryProvider).fetchStatus();
    if (!ref.mounted) {
      return; // 조회가 끝나기 전에 화면을 떠났으면(provider 폐기) 상태를 건드리지 않는다.
    }
    state = result.when(onSuccess: _stateFromOutcome, onFailure: _stateFromLoadFailure);
  }

  /// 서버가 알려준 상태만 반영한 새 상태. 입력하던 실명·사진은 더 필요 없으므로 비운다.
  /// 반려 상태면 사유를 `errorMessage` 에 실어, 화면이 폼 위 배너로 보여줄 수 있게 한다(Task A11).
  StudentVerificationUiState _stateFromOutcome(VerificationOutcome outcome) {
    return StudentVerificationUiState(
      status: outcome.status,
      isLoadingStatus: false,
      errorMessage: outcome.status == _rejectedStatus ? outcome.rejectReason : null,
    );
  }

  /// 조회가 실패하면 지금 아는 상태를 그대로 둔다.
  /// 대기 중(pending) 폴링이 한 번 실패했다고 상태를 'none' 으로 떨어뜨리면
  /// 검토 중인 사용자에게 빈 제출 폼이 다시 열려 중복 제출로 이어진다(Task A11 리뷰).
  StudentVerificationUiState _stateFromLoadFailure(Failure failure) {
    return StudentVerificationUiState(
      isLoadingStatus: false,
      status: state.status,
      errorMessage: failure.toDisplayMessage(),
    );
  }

  void changeRealName(String value) {
    state = _copyWith(realNameInput: value, realName: RealName.tryParse(value));
  }

  /// 갤러리에서 사진을 고른다. 사용자가 고르지 않고 닫으면 아무 일도 하지 않는다.
  Future<void> pickPhoto() async {
    final picked = await pickFromGallery();
    if (picked == null) {
      return;
    }
    state = _copyWith(selectedPhoto: picked);
  }

  /// 압축 → 얼굴 검출 → 업로드 순으로 제출한다.
  /// 실명·사진이 아직 없으면 아무 일도 하지 않는다.
  Future<void> submit() async {
    final realName = state.realName;
    final photo = state.selectedPhoto;
    if (realName == null || photo == null) {
      return;
    }
    // 지난 시도의 실패 문구가 로딩 중에 남아 있지 않도록 지운다.
    state = _copyWith(isSubmitting: true, errorMessage: null);
    final compressed = await _compressedPhotoWithFace(photo);
    await _uploadOrStop(realName, compressed);
  }

  /// 압축한 사진을 돌려준다. 얼굴이 없거나 사진 자체를 처리하지 못하면 `null`.
  /// 압축·검출 플러그인은 읽을 수 없는 사진에 `PlatformException` 등을 던지는데, 그대로 새어 나가면
  /// `isSubmitting` 이 true 로 굳어 CTA 가 앱을 다시 켤 때까지 죽는다 — 여기서 흡수한다.
  Future<File?> _compressedPhotoWithFace(File photo) async {
    try {
      final compressed = await ref.read(imageCompressorProvider).compressToJpeg(photo);
      final hasFace = await ref.read(faceDetectorProvider).hasFace(compressed);
      return hasFace ? compressed : null;
    } on Exception {
      return null;
    }
  }

  /// 쓸 수 있는 사진이 없으면 서버를 부르지 않고 끝낸다(설계 §7.3, 기기 안 1차 필터).
  /// 얼굴이 없는 경우와 사진을 처리하지 못한 경우는 사용자가 할 일이 "다시 올리기"로 같아 문구도 같다.
  Future<void> _uploadOrStop(RealName realName, File? photo) async {
    if (photo == null) {
      state = _copyWith(isSubmitting: false, errorMessage: const NoFaceDetectedFailure().toDisplayMessage());
      return;
    }
    final result = await ref.read(studentVerificationRepositoryProvider).submit(realName, photo);
    state = result.when(
      onSuccess: _stateFromOutcome,
      onFailure: (failure) => _copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  /// 넘긴 필드만 바꾼 새 상태를 만든다.
  /// `realName`·`errorMessage` 는 [_keep] 기본값이라 `null` 을 넘기면 실제로 값이 지워진다.
  StudentVerificationUiState _copyWith({
    String? realNameInput,
    Object? realName = _keep,
    File? selectedPhoto,
    bool? isSubmitting,
    bool? isLoadingStatus,
    String? status,
    Object? errorMessage = _keep,
  }) {
    return StudentVerificationUiState(
      realNameInput: realNameInput ?? state.realNameInput,
      realName: identical(realName, _keep) ? state.realName : realName as RealName?,
      selectedPhoto: selectedPhoto ?? state.selectedPhoto,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      isLoadingStatus: isLoadingStatus ?? state.isLoadingStatus,
      status: status ?? state.status,
      errorMessage: identical(errorMessage, _keep) ? state.errorMessage : errorMessage as String?,
    );
  }
}
