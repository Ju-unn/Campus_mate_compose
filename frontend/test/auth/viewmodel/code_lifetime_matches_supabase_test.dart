import 'dart:io';

import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱이 보여주는 만료 시간과 Supabase Auth 의 `otp_expiry` 는 **같은 값이어야 한다**.
/// 한쪽만 바꾸면 화면은 만료라고 말하는데 서버는 코드를 받아 주거나(또는 그 반대) 한다.
void main() {
  test('codeLifetime 이 supabase/config.toml 의 otp_expiry 와 같다', () {
    // 경로는 `frontend/` 에서 돌릴 때 기준이다(`flutter test` 기본 작업 폴더).
    final config = File('../supabase/config.toml').readAsStringSync();
    final match = RegExp(r'^otp_expiry\s*=\s*(\d+)', multiLine: true).firstMatch(config);

    expect(match, isNotNull, reason: 'config.toml 에서 otp_expiry 를 찾지 못했다');
    expect(int.parse(match!.group(1)!), codeLifetime.inSeconds);
  });
}
