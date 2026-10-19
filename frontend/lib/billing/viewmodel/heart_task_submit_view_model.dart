import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';
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
/// [remaining] 장까지 고르게 한다. 1 이면 image_picker 가 한 장 고르기로 바꿔 준다.
Future<List<File>> _pickFromGallery(int remaining) async {
  final picked = await ImagePicker().pickMultiImage(limit: remaining);
  return [for (final file in picked) File(file.path)];
}

final heartTaskSubmitViewModelProvider =
    NotifierProvider.autoDispose<HeartTaskSubmitViewModel, HeartTaskSubmitUiState>(HeartTaskSubmitViewModel.new);

/// 18b · 18b-2. 사진 고르기(최대 3장) → 압축 → 한 번에 올리기.
class HeartTaskSubmitViewModel extends Notifier<HeartTaskSubmitUiState> {
  /// 테스트에서 갤러리 호출을 대체하기 위한 훅. 기본은 실제 image_picker. 인자는 더 고를 수 있는 장수.
  Future<List<File>> Function(int remaining) pickFromGallery = _pickFromGallery;

  @override
  HeartTaskSubmitUiState build() => const HeartTaskSubmitUiState();

  /// 사진을 [maxPhotos] 장까지 더 고른다(고른 순서대로 뒤에 붙는다). 고르지 않고 닫으면 아무것도 하지 않는다.
  /// 보내는 중에는 사진을 바꾸지 않는다. [maxPhotos] 는 항목의 서버 값 — 옛 서버면 1 이다.
  Future<void> addPhotos({int maxPhotos = HeartTaskSubmitUiState.defaultMaxPhotos}) async {
    if (state.isSubmitting || !state.hasRoomFor(maxPhotos)) return;
    final picked = await pickFromGallery(maxPhotos - state.photos.length);
    if (picked.isEmpty || !ref.mounted) return;
    // 고르는 사이에 상태가 바뀌었을 수 있다 — 지금 상태 뒤에 붙이고 자리를 넘긴 사진은 버린다.
    state = HeartTaskSubmitUiState(photos: [...state.photos, ...picked].take(maxPhotos).toList());
  }

  /// [index] 번째 사진을 뺀다. 없는 자리이거나 보내는 중이면 무시한다.
  void removePhoto(int index) {
    if (state.isSubmitting || index < 0 || index >= state.photos.length) return;
    state = HeartTaskSubmitUiState(photos: [...state.photos]..removeAt(index));
  }

  Future<void> submit(HeartTaskKind kind) async {
    if (!state.canSubmit) return;
    final photos = state.photos;
    state = HeartTaskSubmitUiState(photos: photos, isSubmitting: true);

    final compressor = ref.read(imageCompressorProvider);
    final compressed = await _compressAll(compressor, photos);
    if (compressed == null) {
      if (!ref.mounted) return;
      state = HeartTaskSubmitUiState(photos: photos, errorMessage: heartTaskPhotoUnreadableMessage);
      return;
    }

    final result = await ref.read(heartTaskRepositoryProvider).submit(kind, compressed);
    // 압축본(인증샷 사본)은 폰에 남기지 않는다 — 다시 보낼 때는 고른 사진에서 다시 압축한다.
    unawaited(_discardAll(compressor, compressed));
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) {
        ref.invalidate(heartTasksViewModelProvider);
        return HeartTaskSubmitUiState(photos: photos, submitted: true);
      },
      onFailure: (failure) {
        // 응답만 끊겼거나 다른 기기가 먼저 냈을 수 있다 — 18a 로 돌아가면 서버 상태가 보이게 다시 읽는다.
        ref.invalidate(heartTasksViewModelProvider);
        return HeartTaskSubmitUiState(
          photos: photos,
          errorMessage: failure is RateLimitedFailure ? heartTaskMonthlyLimitMessage : failure.toDisplayMessage(),
        );
      },
    );
  }
}

/// 모든 장을 압축한다. 한 장이라도 못 읽으면 null — 그때까지 만든 압축본은 지운다(보내지 않을 사본을 폰에 남기지 않는다).
Future<List<File>?> _compressAll(ImageCompressor compressor, List<File> photos) async {
  final compressed = <File>[];
  for (final photo in photos) {
    try {
      compressed.add(await compressor.compressToJpeg(photo));
    } on Exception {
      await _discardAll(compressor, compressed);
      return null;
    }
  }
  return compressed;
}

Future<void> _discardAll(ImageCompressor compressor, List<File> compressed) async {
  for (final file in compressed) {
    await compressor.discard(file);
  }
}
