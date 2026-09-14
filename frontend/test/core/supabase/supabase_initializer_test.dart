import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:campus_mate/core/supabase/supabase_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 설정이 채워진 경우는 실제 Supabase 에 연결하므로 네트워크 없는 단위 테스트에서 다루지 않는다.
  test('설정이 비어 있으면 연결하지 않고 StateError 를 던진다', () {
    const config = SupabaseConfig(url: '', anonKey: '');

    expect(() => SupabaseInitializer.run(config), throwsStateError);
  });
}
