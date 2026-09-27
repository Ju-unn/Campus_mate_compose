import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('사유 다섯 개를 서버 값·화면 문구와 짝지어 둔다', () {
    // 값과 순서는 서버 `reasons.py` 와 같다(계획서 B1 표).
    expect(ReportReason.values.map((reason) => reason.wire), [
      'abuse',
      'sexual',
      'spam',
      'fake',
      'other',
    ]);
    // 문구는 서버 문구(운영자용)가 아니라 pen `yl8gX` 행 문구다(xarhn · AMxAh · w8qR7 · BHphm · YhPFL).
    expect(ReportReason.values.map((reason) => reason.label), [
      '욕설·비방·혐오',
      '성적 불쾌감',
      '광고·스팸',
      '사칭·허위',
      '기타',
    ]);
  });

  test('기타 메모는 200자까지다', () {
    expect(reportNoteMaxLength, 200);
  });
}
