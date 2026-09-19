import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('숫자 6자리면 값을 만든다', () {
    final code = VerificationCode.tryParse('123456');
    expect(code, isNotNull);
    expect(code!.toRequestValue(), '123456');
  });

  test('앞뒤 공백은 잘라낸다', () {
    final code = VerificationCode.tryParse(' 123456 ');
    expect(code!.toRequestValue(), '123456');
  });

  test('6자리가 아니면 null', () {
    expect(VerificationCode.tryParse('12345'), isNull);
    expect(VerificationCode.tryParse('1234567'), isNull);
  });

  test('숫자가 아닌 문자가 섞이면 null', () {
    expect(VerificationCode.tryParse('12345a'), isNull);
  });

  test('같은 값이면 동등하다', () {
    expect(VerificationCode.tryParse('123456'), VerificationCode.tryParse('123456'));
  });
}
