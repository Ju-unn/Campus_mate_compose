import 'dart:io';

/// 18b 인증샷 제출의 상태. 동작 하나가 끝날 때마다 새로 만든다 — [errorMessage] 는 그 한 번에만 붙는다.
class HeartTaskSubmitUiState {
  const HeartTaskSubmitUiState({this.photos = const [], this.isSubmitting = false, this.errorMessage, this.submitted = false});

  /// 한 번에 낼 수 있는 사진 수의 기본값 — 서버 `max_photos`(인증 항목 3)와 같다. 옛 서버는 1 을 주므로 화면이 항목의 값을 넘긴다.
  static const int defaultMaxPhotos = 3;

  /// 고른 순서대로. 보내는 사진도 이 순서다.
  final List<File> photos;
  final bool isSubmitting;

  /// 화면이 토스트로 한 번 띄운다.
  final String? errorMessage;

  /// 성공하면 화면이 18c 로 넘어간다.
  final bool submitted;

  bool get canSubmit => photos.isNotEmpty && !isSubmitting && !submitted;

  /// 사진을 더 고를 자리가 [maxPhotos] 안에 남았나.
  bool hasRoomFor(int maxPhotos) => photos.length < maxPhotos;
}
