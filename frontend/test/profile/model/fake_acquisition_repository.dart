import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/acquisition_repository.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// 테스트 전용 [AcquisitionRepository]. 마지막으로 보낸 값을 [submitted] 에 남긴다(안 보냈으면 null).
class FakeAcquisitionRepository implements AcquisitionRepository {
  Result<void> nextResult = const Success(null);
  (AcquisitionChannel, String?)? submitted;
  int submitCount = 0;

  @override
  Future<Result<void>> submit(AcquisitionChannel channel, String? note) async {
    submitCount++;
    submitted = (channel, note);
    return nextResult;
  }
}
