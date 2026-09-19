import 'package:campus_mate/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('주입값이 없는 테스트 환경에서는 apiBaseUrl 이 비어 있다', () {
    expect(Env.apiBaseUrl, '');
  });
}
