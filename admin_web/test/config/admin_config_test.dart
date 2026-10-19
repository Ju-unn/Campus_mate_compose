import 'package:campus_mate_admin/config/admin_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('세 값이 모두 있으면 설정이 갖춰졌다', () {
    const config = AdminConfig(supabaseUrl: 'https://a', supabaseAnonKey: 'k', apiBaseUrl: 'https://b');

    expect(config.isComplete, isTrue);
    expect(config.missingKeys(), isEmpty);
  });

  test('비었거나 공백뿐인 값은 이름으로 알려 준다', () {
    const config = AdminConfig(supabaseUrl: ' ', supabaseAnonKey: 'k', apiBaseUrl: '');

    expect(config.isComplete, isFalse);
    expect(config.missingKeys(), ['SUPABASE_URL', 'API_BASE_URL']);
  });

  test('dart-define 없이 빌드하면 세 값 모두 빠졌다고 본다', () {
    const config = AdminConfig.fromEnvironment();

    expect(config.missingKeys(), ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'API_BASE_URL']);
  });
}
