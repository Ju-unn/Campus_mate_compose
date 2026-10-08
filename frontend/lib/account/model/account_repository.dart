import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 내 계정(서버 `app/account/`). 16e 계정 정보, 탈퇴와 내 카카오톡 아이디 읽기.
abstract interface class AccountRepository {
  /// 16e 가 그리는 계정 정보.
  Future<Result<AccountInfo>> fetchAccount();

  /// 탈퇴. 이미 탈퇴한 계정이면 `WithdrawnFailure` 가 온다 — 성공으로 볼지는 ViewModel 이 정한다.
  Future<Result<void>> withdraw();

  /// 저장된 내 카카오톡 아이디. 없으면 null.
  Future<Result<String?>> fetchKakaoId();
}

/// [AccountRepository] 를 FastAPI 호출로 구현한다. 16e 로그인 수단은 서버가 싣지 않아 세션에서 읽는다.
class HttpAccountRepository implements AccountRepository {
  const HttpAccountRepository(this._api, this._auth);

  final ApiClient _api;
  final GoTrueClient _auth;

  @override
  Future<Result<AccountInfo>> fetchAccount() => _api.send('GET', '/account', (body) {
        final json = body as Map<String, dynamic>;
        return AccountInfo(
          loginProvider: _loginProvider(),
          realName: json['real_name'] as String?,
          birthYear: json['birth_year'] as int?,
          university: json['university'] as String,
          joinedAt: DateTime.parse(json['joined_at'] as String),
          kakaoId: json['kakao_id'] as String?,
        );
      });

  String? _loginProvider() {
    final provider = _auth.currentUser?.appMetadata['provider'];
    return provider is String ? provider : null;
  }

  @override
  Future<Result<void>> withdraw() => _api.send('POST', '/account/withdraw', (_) {});

  @override
  Future<Result<String?>> fetchKakaoId() =>
      _api.send('GET', '/account/kakao-id', (body) => (body as Map<String, dynamic>)['kakao_id'] as String?);
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return HttpAccountRepository(ref.read(apiClientProvider), Supabase.instance.client.auth);
});
