import 'package:campus_mate/graduate/model/verification_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 문자열(wire)이 계약과 글자까지 같다', () {
    expect(VerificationMethod.schoolEmail.wire, 'school_email');
    expect(VerificationMethod.graduateCertificate.wire, 'graduate_certificate');
  });

  test('tryParse 는 서버 문자열을 되읽고, 모르는 값 · null 은 null 이다', () {
    expect(VerificationMethod.tryParse('school_email'), VerificationMethod.schoolEmail);
    expect(VerificationMethod.tryParse('graduate_certificate'), VerificationMethod.graduateCertificate);
    expect(VerificationMethod.tryParse('phone'), isNull);
    expect(VerificationMethod.tryParse(null), isNull);
    expect(VerificationMethod.tryParse(3), isNull);
  });
}
