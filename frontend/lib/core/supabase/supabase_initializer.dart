import 'package:campus_mate/core/supabase/supabase_config.dart';

/// 앱 시작 시 Supabase 연결을 준비한다.
///
/// 설정 검증(SupabaseConfig)과 실제 연결을 나눠 두어
/// 검증 로직을 네트워크 없이 테스트할 수 있게 했다.
abstract final class SupabaseInitializer {
  /// 설정이 불완전하면 즉시 예외를 던져 잘못된 빌드를 조기에 드러낸다.
  static Future<void> run(SupabaseConfig config) {
    if (config.isComplete()) {
      return config.connect();
    }
    throw StateError(
      'Supabase 설정이 비어 있습니다. '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... '
      '를 붙여 실행하세요.',
    );
  }
}
