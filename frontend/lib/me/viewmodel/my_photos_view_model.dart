import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final myPhotosViewModelProvider =
    NotifierProvider.autoDispose<MyPhotosViewModel, PhotosUiState>(MyPhotosViewModel.new);

/// 15-7 사진 수정(pen `szJ79`, 계획서 2026-09-27-me-edit.md A6). 04-2 의 고르기 · 얼굴 검사 · 빼기 · 맞바꾸기를 그대로
/// 쓰고, 칸을 서버 사진으로 채워 "저장" 한 번에 올린다(U2).
///
/// 편집 모드. 열 때마다 서버 값으로 채운다 — autoDispose 라 닫으면 고르다 만 값이 남지 않는다(Review Focus 5).
/// 저장이 끝나면 내 프로필을 다시 읽게 하고(invalidate) 15-5 로 돌아간다(N8). 온보딩 단계 조회는 부르지 않는다.
class MyPhotosViewModel extends PhotosViewModel {
  /// 내 프로필을 watch 하지 않고 read 한다 — 저장 뒤 다시 읽혀도 고르던 칸이 서버 값으로 되돌아가지 않게(15c 와 같다).
  @override
  PhotosUiState build() {
    final profile = ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    return PhotosUiState(
      photos: [
        for (final photo in profile?.photos ?? const <MyPhoto>[])
          SelectedPhoto.saved(id: photo.id, url: photo.url, isAvatarSource: photo.isAvatarSource),
      ],
    );
  }

  /// 2~4장이고, 고른 사진을 살펴보는 중도 저장 중도 아닐 때 — 늦게 끝난 검사가 보낸 목록에서 빠지지 않게(04-2 "다음" 과 같다).
  bool get canSave => state.canProceed && !state.isCheckingPhotos && !state.isSubmitting;

  /// 칸 순서 그대로 올린다. 아바타 원본을 뺐으면 대표(첫 칸)가 원본이 된다(사용자 결정 U3, 2026-09-27) —
  /// 지금 아바타는 그대로고, 다음 "아바타 다시 만들기" 가 이 사진으로 만든다.
  Future<void> save() async {
    if (!canSave) {
      return;
    }
    final sourceIndex = state.photos.indexWhere((p) => p.isAvatarSource);
    final slots = [for (final p in state.photos) p.id != null ? KeptPhoto(p.id!) : NewPhoto(p.file!)];
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    // 저장 중에 뒤로 나가도 끝까지 저장하고 15-5 를 다시 읽게 한다 — 그동안 autoDispose 가 버리지 않게 붙잡는다.
    final keepAlive = ref.keepAlive();
    try {
      final result = await ref.read(meRepositoryProvider).savePhotos(slots, sourceIndex < 0 ? 0 : sourceIndex);
      state = result.when(
        onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
        onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
      );
      // 실패해도 다시 읽는다 — 서버는 여러 요청으로 나눠 바꿔 중간에 멈출 수 있고(계획서 2-2 ⑤~⑦), 409 "다시 열어 주세요"
      // 뒤에 다시 열면 지금 서버 값으로 채워져야 한다. 칸은 그대로 둔다(build 는 read 라 다시 읽혀도 안 바뀐다).
      ref.invalidate(myProfileProvider);
    } finally {
      keepAlive.close();
    }
  }
}
