import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 내 계정(서버 `app/account/`). 탈퇴와 내 카카오톡 아이디 읽기.
abstract interface class AccountRepository {
  /// 탈퇴. 이미 탈퇴한 계정이면 `WithdrawnFailure` 가 온다 — 성공으로 볼지는 ViewModel 이 정한다.
  Future<Result<void>> withdraw();

  /// 저장된 내 카카오톡 아이디. 없으면 null.
  Future<Result<String?>> fetchKakaoId();
}

/// [AccountRepository] 를 FastAPI 호출로 구현한다.
class HttpAccountRepository implements AccountRepository {
  const HttpAccountRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> withdraw() => _api.send('POST', '/account/withdraw', (_) {});

  @override
  Future<Result<String?>> fetchKakaoId() =>
      _api.send('GET', '/account/kakao-id', (body) => (body as Map<String, dynamic>)['kakao_id'] as String?);
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return HttpAccountRepository(ref.read(apiClientProvider));
});
