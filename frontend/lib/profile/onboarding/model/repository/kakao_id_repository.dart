import 'package:campus_mate/common/result.dart';

abstract interface class KakaoIdRepository {
  Future<Result<void>> submit(String kakaoId);
}
