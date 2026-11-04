import 'package:campus_mate/safety/model/data/report_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('사유 다섯 개를 서버 값과 짝지어 둔다', () {
    // 값과 순서는 서버 `reasons.py` 와 같다(계획서 B1 표).
    expect(ReportReason.values.map((reason) => reason.wire), [
      'abuse',
      'sexual',
      'spam',
      'fake',
      'other',
    ]);
  });

  test('기타 메모는 200자까지다', () {
    expect(reportNoteMaxLength, 200);
  });
}
