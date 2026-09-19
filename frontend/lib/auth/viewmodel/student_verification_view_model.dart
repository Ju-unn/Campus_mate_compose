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
    Future.microtask(_loadStatus);
    return const StudentVerificationUiState();
  }

  Future<void> _loadStatus() async {
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

  StudentVerificationUiState _stateFromLoadFailure(Failure failure) {
    return StudentVerificationUiState(isLoadingStatus: false, errorMessage: failure.toDisplayMessage());
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
    final compressed = await ref.read(imageCompressorProvider).compressToJpeg(photo);
    await _uploadIfFaceFound(realName, compressed);
  }

  /// 얼굴이 보이지 않으면 서버를 부르지 않고 끝낸다(설계 §7.3, 기기 안 1차 필터).
  Future<void> _uploadIfFaceFound(RealName realName, File photo) async {
    if (!await ref.read(faceDetectorProvider).hasFace(photo)) {
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
