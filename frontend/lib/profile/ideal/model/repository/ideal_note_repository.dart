import 'package:campus_mate/common/result.dart';

abstract interface class IdealNoteRepository {
  /// 06-2a "이런 사람이 좋아요" 자유 글. 필수라 빈 글은 보내지 않는다
  /// (2026-09-20 사용자 결정, 서버도 공백만 쓴 글을 422 로 막는다).
  Future<Result<void>> submit(String note);
}
