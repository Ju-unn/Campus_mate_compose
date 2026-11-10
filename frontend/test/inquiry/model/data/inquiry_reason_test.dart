import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('사유 여섯 개가 pen 21b 순서이고 서버 reasons.py 코드와 같다', () {
    expect(InquiryReason.values.map((reason) => reason.wire), [
      'account',
      'payment',
      'matching',
      'safety',
      'bug',
      'other',
    ]);
  });

  test('내용 상한은 서버 BODY_MAX 1000 이다', () {
    expect(inquiryBodyMaxLength, 1000);
  });
}
