import 'dart:convert';

import 'package:campus_mate/auth/model/supabase_school_email_repository.dart';
import 'package:campus_mate/auth/model/temporary_auth_connection.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 학교 메일 인증(임시 연결)이 메인(소셜) 세션을 건드리지 않는지 고정한다.
///
/// 앱과 똑같이 `Supabase.initialize` 로 메인 연결을 켜고, 저장돼 있던 소셜 세션을 되살린 상태에서 시작한다.
/// 임시 연결이 메인 연결로 바뀌면(실수로 `Supabase.instance.client.auth` 를 쓰면) 메인 세션의 사용자가
/// 임시 이메일 계정으로 바뀌고 라우터 리스너가 울린다 — 이 파일이 그것을 잡는다.
const _projectUrl = 'https://project.test';
const _anonKey = 'anon-key';
const _mainUserId = 'main-social-user';
const _temporaryUserId = 'temporary-email-user';

Map<String, Object?> _sessionJson(String userId, String accessToken, String provider) => {
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_in': 3600,
  // 만료가 멀어야 되살릴 때 갱신(네트워크)을 하지 않는다.
  'expires_at': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
  'refresh_token': 'refresh-$userId',
  'user': {
    'id': userId,
    'aud': 'authenticated',
    'app_metadata': {'provider': provider},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-10-01T00:00:00Z',
  },
};

/// 기기에 저장돼 있던 메인(소셜) 세션. 앱을 켤 때 supabase_flutter 가 이것을 되살린다.
class _PersistedMainSession extends LocalStorage {
  String? _stored = jsonEncode(_sessionJson(_mainUserId, 'main-token', 'kakao'));

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => _stored != null;

  @override
  Future<String?> accessToken() async => _stored;

  @override
  Future<void> persistSession(String persistSessionString) async => _stored = persistSessionString;

  @override
  Future<void> removePersistedSession() async => _stored = null;
}

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

/// GoTrue 흉내. 메인 · 임시 연결이 같은 주소를 쓰므로 둘 다 이 하나가 받는다.
final _gotrue = MockClient((request) async {
  final path = request.url.path;
  if (path.endsWith('/auth/v1/verify')) {
    return http.Response(
      jsonEncode(_sessionJson(_temporaryUserId, 'temporary-token', 'email')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('{}', 200, headers: {'content-type': 'application/json'});
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: _projectUrl,
      publishableKey: _anonKey,
      httpClient: _gotrue,
      authOptions: FlutterAuthClientOptions(
        localStorage: _PersistedMainSession(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  test('학교 메일 인증번호를 받고 확인해도 메인 세션의 사용자와 상태 알림이 그대로다', () async {
    final mainAuth = Supabase.instance.client.auth;
    expect(mainAuth.currentUser?.id, _mainUserId, reason: '시작 전 — 저장된 소셜 세션이 되살아났다');
    final listenable = AuthSessionListenable(Supabase.instance.client);
    addTearDown(listenable.dispose);
    // gotrue 의 인증 스트림은 마지막 이벤트(되살린 세션)를 새 구독자에게 한 번 다시 준다 — 그것을 흘려보낸 뒤 센다.
    await pumpEventQueue();
    var notified = 0;
    listenable.addListener(() => notified++);
    final sentToApi = <http.Request>[];
    final api = ApiClient(
      'https://api.test',
      MockClient((request) async {
        sentToApi.add(request);
        return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
      }),
      mainAuth,
    );
    final repository = SupabaseSchoolEmailRepository(
      api,
      TemporaryAuthConnection(
        () => const SupabaseConfig(url: _projectUrl, anonKey: _anonKey).openTemporaryAuth(httpClient: _gotrue),
      ),
    );
    final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

    await repository.requestCode(email);
    final token = await repository.verifyCode(email, VerificationCode.tryParse('123456')!);
    // 인증 이벤트는 스트림으로 늦게 온다 — 다 흘려보낸 뒤에 센다.
    await pumpEventQueue();

    expect(token.when(onSuccess: (value) => value, onFailure: (_) => null), 'temporary-token');
    expect(mainAuth.currentUser?.id, _mainUserId);
    expect(mainAuth.currentSession?.accessToken, 'main-token');
    expect(listenable.isAuthenticated, isTrue);
    expect(notified, 0, reason: '임시 연결의 로그인 이벤트가 메인 세션 리스너에 닿았다');

    await repository.complete('temporary-token');
    await pumpEventQueue();

    // 서버에는 메인(소셜) 토큰으로 인증하고, 임시 토큰은 본문에만 싣는다.
    expect(sentToApi.single.headers['Authorization'], 'Bearer main-token');
    expect(jsonDecode(sentToApi.single.body), {'temp_access_token': 'temporary-token'});
    // 임시 연결을 로그아웃해도 메인 세션은 그대로다.
    expect(mainAuth.currentUser?.id, _mainUserId);
    expect(notified, 0, reason: '임시 연결의 로그아웃 이벤트가 메인 세션 리스너에 닿았다');
  });
}
