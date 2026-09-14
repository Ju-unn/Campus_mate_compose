import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('url 과 anonKey 가 모두 있으면 설정이 완전하다', () {
    const config = SupabaseConfig(
      url: 'https://example.supabase.co',
      anonKey: 'anon-key',
    );

    expect(config.isComplete(), isTrue);
  });

  test('url 이 비어 있으면 설정이 완전하지 않다', () {
    const config = SupabaseConfig(url: '', anonKey: 'anon-key');

    expect(config.isComplete(), isFalse);
  });

  test('anonKey 가 비어 있으면 설정이 완전하지 않다', () {
    const config = SupabaseConfig(
      url: 'https://example.supabase.co',
      anonKey: '',
    );

    expect(config.isComplete(), isFalse);
  });

  test('공백만 있는 값은 비어 있는 것으로 본다', () {
    const config = SupabaseConfig(url: '   ', anonKey: 'anon-key');

    expect(config.isComplete(), isFalse);
  });

  test('주입값이 없는 테스트 환경에서는 설정이 완전하지 않다', () {
    final config = SupabaseConfig.fromEnvironment();

    expect(config.isComplete(), isFalse);
  });
}
