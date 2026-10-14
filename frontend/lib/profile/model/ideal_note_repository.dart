import 'package:campus_mate/common/result.dart';

/// "이런 사람이 좋아요" 화면 상한(06-2a, 2026-10-14 사용자 결정 "추천대로"). 서버 상한(1000자)보다 작다. 코드포인트로 센다.
/// 최소 10자 규칙은 그대로다(`IdealNoteUiState.minLength`).
const int idealNoteMaxLength = 300;

/// 엔터로 만드는 줄 상한 — 06-2a 칸 maxLines 와 같다.
const int idealNoteMaxLines = 6;

abstract interface class IdealNoteRepository {
  /// 06-2a "이런 사람이 좋아요" 자유 글. 필수라 빈 글은 보내지 않는다
  /// (2026-09-20 사용자 결정, 서버도 공백만 쓴 글을 422 로 막는다).
  Future<Result<void>> submit(String note);
}
