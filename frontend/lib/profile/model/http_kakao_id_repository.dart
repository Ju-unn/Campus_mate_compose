import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/model/kakao_id_repository.dart';

/// [KakaoIdRepository]를 FastAPI 호출로 구현한다.
class HttpKakaoIdRepository implements KakaoIdRepository {
  const HttpKakaoIdRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit(String kakaoId) =>
      _api.send('POST', '/profile-onboarding/kakao-id', (_) {}, body: {'kakao_id': kakaoId});
}
