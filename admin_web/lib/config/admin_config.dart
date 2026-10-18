/// 빌드 때 `--dart-define` 으로 받는 접속 정보. 값은 코드에 쓰지 않는다(frontend/CLAUDE.md §10.1).
/// 브라우저로 내려가는 값이라 공개해도 되는 것만 넣는다 — Supabase anon 키와 주소뿐이고 service_role 키는 서버 전용이다.
class AdminConfig {
  const AdminConfig({required this.supabaseUrl, required this.supabaseAnonKey, required this.apiBaseUrl});

  const AdminConfig.fromEnvironment()
      : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
        apiBaseUrl = const String.fromEnvironment('API_BASE_URL');

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String apiBaseUrl;

  bool get isComplete => missingKeys().isEmpty;

  /// 비었거나 공백뿐인 값의 dart-define 이름. "설정 누락" 화면이 그대로 보여 준다.
  List<String> missingKeys() {
    final values = <String, String>{
      'SUPABASE_URL': supabaseUrl,
      'SUPABASE_ANON_KEY': supabaseAnonKey,
      'API_BASE_URL': apiBaseUrl,
    };
    return [for (final entry in values.entries) if (entry.value.trim().isEmpty) entry.key];
  }
}
