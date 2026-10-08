import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 온보딩 화면에서 쓰던 값을 폰에 잠시 남긴다. 앱이 중간에 꺼져도 다시 열면 그 단계에서 이어 쓴다.
///
/// 늘 **지금 로그인한 계정**의 값만 다룬다 — 다른 계정으로 들어오면 앞사람 값은 보이지 않는다.
/// 서버에 보내지 않는 임시 값이라 앱 데이터를 지우거나 다시 설치하면 사라진다.
abstract interface class DraftStore {
  /// [screen] 에 남긴 값을 [decode] 로 읽는다. 없거나, 로그인 전이거나, 버전이 다르거나,
  /// [decode] 가 모양이 안 맞아 던지면 그 값을 **조용히 버리고** null 을 준다(앱 업데이트 뒤에도 깨지지 않게).
  T? read<T>(DraftScreen screen, T Function(Map<String, Object?> data) decode);

  /// [data] 를 남긴다. 곧바로 쓰지 않고 잠깐 모았다가 마지막 값만 쓴다(디바운스) — 글자마다 디스크를 두드리지 않는다.
  /// [files] 는 이 값과 함께 지울 임시 파일 경로다(고른 사진).
  void write(DraftScreen screen, Map<String, Object?> data, {List<String> files = const []});

  /// [screen] 의 값과 딸린 파일을 지운다 — 그 단계 "다음" 이 성공했을 때.
  Future<void> clear(DraftScreen screen);

  /// **모든 계정**의 값과 딸린 파일을 지운다 — 로그아웃 · 탈퇴할 때.
  Future<void> clearAll();
}

/// 아무것도 남기지 않는 저장소. [draftStoreProvider] 의 기본값이다.
///
/// 진짜 저장소(`SharedPreferencesDraftStore`)는 앱을 켤 때 디스크를 한 번 읽어 와야 해서 main.dart 가
/// `SessionScope` 로 바꿔 끼운다. 바꿔 끼우지 않은 시험 · 통합 시험 하네스는 예전처럼 메모리에만 들고 있다.
class NoDraftStore implements DraftStore {
  const NoDraftStore();

  @override
  T? read<T>(DraftScreen screen, T Function(Map<String, Object?> data) decode) => null;

  @override
  void write(DraftScreen screen, Map<String, Object?> data, {List<String> files = const []}) {}

  @override
  Future<void> clear(DraftScreen screen) async {}

  @override
  Future<void> clearAll() async {}
}

/// 온보딩 뷰모델이 처음 상태를 만들 때 읽고, 값이 바뀔 때 쓰는 단 하나의 자리.
final draftStoreProvider = Provider<DraftStore>((ref) => const NoDraftStore());
