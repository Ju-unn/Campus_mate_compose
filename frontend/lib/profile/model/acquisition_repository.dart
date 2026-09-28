import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

abstract interface class AcquisitionRepository {
  /// 20d 유입경로. [note] 는 `기타` 일 때만 싣는다 — 다른 칩이면 서버도 저장하지 않는다.
  Future<Result<void>> submit(AcquisitionChannel channel, String? note);
}
