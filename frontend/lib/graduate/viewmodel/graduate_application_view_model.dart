import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';
import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository_provider.dart';
import 'package:campus_mate/graduate/model/previous_school_email.dart';
import 'package:campus_mate/graduate/viewmodel/graduate_application_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 압축이 사진을 못 읽었을 때. 서버 `errors.PHOTO_UNREADABLE` 과 같은 문구.
const String graduatePhotoUnreadableMessage = '사진을 다시 확인해 주세요';

/// 서버가 "지금 관문이 달라졌다" 고 알려 주는 코드(다른 기기가 먼저 냈다 · 그새 인증이 끝났다).
/// 문구만 보이면 폼에 갇히므로 관문을 다시 물어 화면을 맞춘다.
const List<String> _gateChangedCodes = ['already_pending', 'already_verified'];

/// image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어 훅으로 갈아끼운다(3b · 18b 와 같다).
Future<File?> _pickFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked == null ? null : File(picked.path);
}

/// image_picker 가 앱 캐시 · 임시 폴더에 만든 사본(또는 우리 압축본)을 지운다. **앱 임시 폴더 밖 파일은 건드리지 않는다** —
/// 사용자의 갤러리 원본일 수 있다. iOS 는 image_picker 가 `tmp` 에, path_provider 의 임시 폴더는 `Caches` 라 둘 다 본다.
/// 이미 없거나 지우지 못해도 그만이다(정리 때문에 신청이 막히면 안 된다).
Future<void> _deleteCopy(File file) async {
  try {
    final roots = [Directory.systemTemp.path, (await getTemporaryDirectory()).path];
    final path = file.absolute.path;
    if (roots.any(path.startsWith)) await file.delete();
  } on Exception {
    return;
  }
}

final graduateApplicationViewModelProvider =
    NotifierProvider.autoDispose<GraduateApplicationViewModel, GraduateApplicationUiState>(
  GraduateApplicationViewModel.new,
);

/// 졸업생 신청 폼(처음 신청 · 반려 뒤 다시 신청). 사진 고르기 → **곧바로 압축** → 올리기. 성공하면 관문을 다시 묻고
/// 화면은 `AuthRedirect` 가 대기 화면으로 옮긴다.
///
/// 졸업증명서는 민감해 폰에 사본을 오래 두지 않는다(독립 검토 사소1, 대장 10-19): 고른 즉시 압축하고 image_picker 가 만든
/// 원본 사본은 그 자리에서 지운다. 압축본([GraduateApplicationUiState.photo])은 올리기에 성공했을 때 · 사진을 빼거나 바꿀 때 ·
/// 화면을 떠날 때(뒤로가기 · 취소) 지운다. 올리기가 실패하면 그대로 둬 다시 눌러 같은 사진을 올린다.
/// 로그아웃 · 탈퇴는 기존 `ImageCompressor.discardAll` 이 압축본 이름으로 쓸어 간다(원본 사본은 이미 없다).
/// 알려진 틈: 고르는 중 · 압축 중에 앱이 죽으면 원본 사본이 캐시에 남는다(OS 가 캐시를 비운다).
class GraduateApplicationViewModel extends Notifier<GraduateApplicationUiState> {
  /// 테스트에서 갤러리 호출을 대체하기 위한 훅. 기본은 실제 image_picker.
  Future<File?> Function() pickFromGallery = _pickFromGallery;

  /// 테스트에서 파일 삭제를 대체하기 위한 훅. 기본은 앱 임시 폴더 안 파일만 지우는 [_deleteCopy].
  Future<void> Function(File file) deleteCopy = _deleteCopy;

  late ImageCompressor _compressor;

  /// 지금 상태에 든 압축본. 화면을 떠날 때 [ref] 를 못 쓰므로 따로 쥔다.
  File? _held;
  bool _picking = false;

  @override
  GraduateApplicationUiState build() {
    _compressor = ref.read(imageCompressorProvider);
    _held = null;
    _picking = false;
    ref.onDispose(_discardHeld);
    Future.microtask(_loadRejection);
    return const GraduateApplicationUiState();
  }

  /// 쥔 압축본을 지운다(없으면 아무것도 안 한다).
  void _discardHeld() {
    final held = _held;
    _held = null;
    if (held != null) _release(held);
  }

  /// 압축기가 만든 이름이면 압축기가, 압축이 원본을 그대로 돌려준 경우(폴백)는 임시 폴더 안일 때만 [deleteCopy] 가 지운다.
  void _release(File file) {
    unawaited(_compressor.discard(file));
    unawaited(deleteCopy(file));
  }

  /// 반려 사유 · 남은 횟수를 읽는다. 못 읽어도 폼은 쓸 수 있다 — 횟수는 서버가 막는다. 사용자가 그새 적은 값은 지키고 두 칸만 더한다.
  Future<void> _loadRejection() async {
    final result = await ref.read(graduateVerificationRepositoryProvider).fetchState();
    if (!ref.mounted) return;
    final loaded = result.when(onSuccess: (loaded) => loaded, onFailure: (_) => null);
    if (loaded is! GraduateRejected) return;
    state = state.copyWith(rejection: loaded, isExhausted: loaded.isExhausted());
  }

  /// 고르지 않고 닫으면 아무것도 하지 않는다. 보내는 중 · 압축하는 중에는 사진을 바꾸지 않는다.
  Future<void> pickPhoto() async {
    if (state.isSubmitting || _picking) return;
    final picked = await pickFromGallery();
    if (picked == null) return;
    if (!ref.mounted) {
      await deleteCopy(picked);
      return;
    }
    _picking = true;
    try {
      await _keepCompressed(picked);
    } finally {
      _picking = false;
    }
  }

  /// 고른 사진을 압축해 상태에 두고 원본 사본을 지운다. 못 읽는 사진이면 두지 않고 안내한다.
  Future<void> _keepCompressed(File picked) async {
    final File compressed;
    try {
      compressed = await _compressor.compressToJpeg(picked);
    } on Exception {
      await deleteCopy(picked);
      if (ref.mounted) state = state.copyWith(errorMessage: graduatePhotoUnreadableMessage);
      return;
    }
    if (compressed.path != picked.path) await deleteCopy(picked);
    if (!ref.mounted) {
      _release(compressed);
      return;
    }
    final previous = _held;
    _held = compressed;
    state = state.copyWith(photo: compressed);
    if (previous != null) _release(previous);
  }

  /// 사진 칸의 삭제 X(pen `oaPh3`). 사진만 비운다 — copyWith 는 null 로 못 비우므로 새 상태를 만든다.
  void removePhoto() {
    if (state.isSubmitting) return;
    _discardHeld();
    state = GraduateApplicationUiState(
      previousEmailInput: state.previousEmailInput,
      agreed: state.agreed,
      rejection: state.rejection,
      isExhausted: state.isExhausted,
    );
  }

  void changePreviousEmail(String value) => state = state.copyWith(previousEmailInput: value);

  void changeAgreed(bool agreed) => state = state.copyWith(agreed: agreed);

  Future<void> submit() async {
    final photo = state.photo;
    if (photo == null || !state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);
    final result = await ref
        .read(graduateVerificationRepositoryProvider)
        .submit(photo, PreviousSchoolEmail.tryParse(state.previousEmailInput));
    if (!ref.mounted) return;
    await result.when(onSuccess: (_) => _finish(), onFailure: _fail);
  }

  /// 올렸다 — 압축본(졸업증명서 사본)은 폰에 남기지 않는다. 실패했을 때만 남겨 다시 보낸다.
  Future<void> _finish() async {
    _discardHeld();
    state = GraduateApplicationUiState(
      previousEmailInput: state.previousEmailInput,
      agreed: state.agreed,
      isSubmitting: true,
      rejection: state.rejection,
      isExhausted: state.isExhausted,
    );
    await ref.read(verificationGateListenableProvider).refresh();
    if (!ref.mounted) return;
    state = state.copyWith(isSubmitting: false);
  }

  /// 429 는 이 엔드포인트에서 신청 횟수 소진뿐이다 — 문구 대신 문의 안내 상태로 바꾼다.
  Future<void> _fail(Failure failure) async {
    if (failure is RateLimitedFailure) {
      state = state.copyWith(isSubmitting: false, isExhausted: true);
      return;
    }
    state = state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage());
    if (failure is ServerRejectedFailure && _gateChangedCodes.any(failure.hasCode)) {
      await ref.read(verificationGateListenableProvider).refresh();
    }
  }
}
