import 'package:supabase_flutter/supabase_flutter.dart';

/// 빌드 시 주입된 Supabase 접속 정보를 담는다.
///
/// 키를 소스에 적지 않고 `--dart-define` 으로 넣는다.
/// 앱은 디컴파일되면 문자열이 그대로 드러나므로,
/// 여기에는 공개해도 되는 anon 키만 들어간다.
class SupabaseConfig {
  // Dart 3.13 private named parameter: 호출부는 url:·anonKey: 로 넘긴다
  const SupabaseConfig({required this._url, required this._anonKey});

  /// 빌드 명령의 --dart-define 값을 읽어 설정을 만든다.
  factory SupabaseConfig.fromEnvironment() {
    return const SupabaseConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  final String _url;
  final String _anonKey;

  /// 접속에 필요한 값이 모두 채워졌는지 확인한다.
  /// 잘못된 설정으로 앱이 뜨는 것을 진입 시점에 막기 위한 것이다.
  bool isComplete() {
    return _url.trim().isNotEmpty && _anonKey.trim().isNotEmpty;
  }

  /// Supabase 클라이언트를 실제로 초기화한다.
  Future<void> connect() {
    // supabase_flutter 2.13 부터 anonKey 매개변수는 deprecated 다.
    // publishableKey 와 같은 자리라서 legacy anon 키를 넣어도 똑같이 동작한다.
    return Supabase.initialize(url: _url, publishableKey: _anonKey);
  }
}
