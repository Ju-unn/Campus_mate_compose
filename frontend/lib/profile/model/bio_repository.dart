import 'package:campus_mate/common/result.dart';

/// 자기소개 화면 상한(06-3 · 15c, 2026-10-14 사용자 결정 "추천대로"). 서버 상한(1000자)보다 작다 —
/// 서버는 그 전에 쓴 긴 소개를 지키려고 1000 을 그대로 둔다. 코드포인트로 센다.
const int bioMaxLength = 300;

/// 엔터로 만드는 줄 상한 — 06-3 칸 maxLines 와 같다.
const int bioMaxLines = 8;

abstract interface class BioRepository {
  /// 06-2b 자기소개 AI 초안. 서버가 최초 1회만 만들어 준다(두 번째부터 409).
  Future<Result<String>> generateDraft();

  /// 06-3 자기소개 저장. 성공하면 온보딩이 끝나 프로필이 활성화된다.
  Future<Result<void>> submit(String bio);
}
