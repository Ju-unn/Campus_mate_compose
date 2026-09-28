import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileEditViewModelProvider =
    NotifierProvider.autoDispose<ProfileEditViewModel, ProfileEditUiState>(ProfileEditViewModel.new);

/// 15c 자기소개 · 태그 수정(pen `zWMxM`, 계획서 A4). 이 화면의 "저장" 은 자기소개만 저장한다 —
/// 태그는 "수정 ›" 로 연 태그 편집 화면이 그 자리에서 저장한다(T5).
///
/// 편집 모드. 열 때마다 서버 값으로 채운다 — autoDispose 라 닫으면 고르다 만 값이 남지 않는다(Review Focus 5).
/// 저장이 끝나면 화면 15 를 다시 읽게 하고(invalidate) 15 로 돌아간다(U4). 온보딩 단계 조회는 부르지 않는다.
class ProfileEditViewModel extends Notifier<ProfileEditUiState> {
  /// 내 프로필을 watch 하지 않고 read 한다 — 태그 편집이 invalidate 해도 쓰던 자기소개가 서버 값으로 되돌아가지 않게.
  @override
  ProfileEditUiState build() {
    final profile = ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    return ProfileEditUiState(bio: profile?.bio ?? '');
  }

  void changeBio(String bio) {
    state = state.copyWith(bio: bio);
  }

  Future<void> save() async {
    if (!state.canSave) {
      return;
    }
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    // 저장 중에 뒤로 나가도 끝까지 저장하고 화면 15 를 다시 읽게 한다 — 그동안 autoDispose 가 버리지 않게 붙잡는다.
    final keepAlive = ref.keepAlive();
    try {
      final result = await ref.read(meRepositoryProvider).updateProfile(bio: state.bio.trim());
      state = result.when(
        onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
        onFailure: (failure) => state.copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
      );
      if (state.completed) {
        ref.invalidate(myProfileProvider);
      }
    } finally {
      keepAlive.close();
    }
  }
}

/// 15c 의 상태. 칩은 여기 없다 — 화면이 내 프로필을 바로 본다(태그 편집이 저장하면 invalidate 로 새 칩이 그려진다).
class ProfileEditUiState {
  const ProfileEditUiState({
    required this.bio,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  final String bio;
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 빈 자기소개는 저장하지 않는다 — 06-3 과 같은 규칙(서버도 422).
  bool get canSave => bio.trim().isNotEmpty && !isSubmitting;

  ProfileEditUiState copyWith({String? bio, bool? isSubmitting, String? errorMessage, bool? completed}) {
    return ProfileEditUiState(
      bio: bio ?? this.bio,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      completed: completed ?? this.completed,
    );
  }
}
