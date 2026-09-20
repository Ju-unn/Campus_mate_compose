import 'package:campus_mate/common/result.dart';

abstract interface class IdealNoteRepository {
  /// 06-2a "이런 사람이 좋아요" 자유 글. 건너뛰면 빈 문자열을 보낸다
  /// (`ideal_note_seen` 컬럼이 없어 non-null 이면 본 것으로 친다).
  Future<Result<void>> submit(String note);
}
