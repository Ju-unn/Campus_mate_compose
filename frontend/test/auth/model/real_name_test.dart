import 'package:campus_mate/auth/model/real_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 문자열이면 null', () {
    expect(RealName.tryParse('   '), isNull);
  });

  test('앞뒤 공백을 잘라낸다', () {
    expect(RealName.tryParse(' 김가나 ')!.toRequestValue(), '김가나');
  });

  test('30자를 넘으면 null', () {
    expect(RealName.tryParse('가' * 31), isNull);
  });
}
