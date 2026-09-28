import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// 월 한도 429. 공용 429 문구("잠시 후 다시 시도")는 달이 바뀌어야 풀리는 한도와 맞지 않아
/// 서버 `errors.HEART_TASK_MONTHLY_LIMIT` 과 같은 문구를 여기 둔다(17b 하루 상한 · 신고 상한과 같은 처리).
const String heartTaskMonthlyLimitMessage = '이번 달에는 더 인증할 수 없어요';

/// 압축이 사진을 못 읽었을 때. 서버 `errors.PHOTO_UNREADABLE` 과 같은 문구.
const String heartTaskPhotoUnreadableMessage = '사진을 다시 확인해 주세요';

/// image_picker 는 플랫폼 플러그인이라 단위 테스트에서 부를 수 없어 훅으로 갈아끼운다(3b 와 같다).
Future<File?> _pickFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked == null ? null : File(picked.path);
}

final heartTaskSubmitViewModelProvider =
    NotifierProvider.autoDispose<HeartTaskSubmitViewModel, HeartTaskSubmitUiState>(HeartTaskSubmitViewModel.new);

/// 18b · 18b-2. 사진 고르기 → 압축 → 올리기.
class HeartTaskSubmitViewModel extends Notifier<HeartTaskSubmitUiState> {
  /// 테스트에서 갤러리 호출을 대체하기 위한 훅. 기본은 실제 image_picker.
  Future<File?> Function() pickFromGallery = _pickFromGallery;

  @override
  HeartTaskSubmitUiState build() => const HeartTaskSubmitUiState();

  /// 고르지 않고 닫으면 아무것도 하지 않는다. 보내는 중에는 사진을 바꾸지 않는다.
  Future<void> pickPhoto() async {
    if (state.isSubmitting) return;
    final picked = await pickFromGallery();
    if (picked == null || !ref.mounted) return;
    state = HeartTaskSubmitUiState(photo: picked);
  }

  Future<void> submit(HeartTaskKind kind) async {
    final photo = state.photo;
    if (photo == null || !state.canSubmit) return;
    state = HeartTaskSubmitUiState(photo: photo, isSubmitting: true);

    final File compressed;
    try {
      compressed = await ref.read(imageCompressorProvider).compressToJpeg(photo);
    } on Exception {
      if (!ref.mounted) return;
      state = HeartTaskSubmitUiState(photo: photo, errorMessage: heartTaskPhotoUnreadableMessage);
      return;
    }

    final result = await ref.read(heartTaskRepositoryProvider).submit(kind, compressed);
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) {
        ref.invalidate(heartTasksViewModelProvider);
        return HeartTaskSubmitUiState(photo: photo, submitted: true);
      },
      onFailure: (failure) {
        // 응답만 끊겼거나 다른 기기가 먼저 냈을 수 있다 — 18a 로 돌아가면 서버 상태가 보이게 다시 읽는다.
        ref.invalidate(heartTasksViewModelProvider);
        return HeartTaskSubmitUiState(
          photo: photo,
          errorMessage: failure is RateLimitedFailure ? heartTaskMonthlyLimitMessage : failure.toDisplayMessage(),
        );
      },
    );
  }
}
