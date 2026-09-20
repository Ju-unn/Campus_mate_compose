import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/kakao_id_repository.dart';

class FakeKakaoIdRepository implements KakaoIdRepository {
  Result<void> nextResult = const Success(null);
  final List<String> submitted = [];

  @override
  Future<Result<void>> submit(String kakaoId) async {
    submitted.add(kakaoId);
    return nextResult;
  }
}
