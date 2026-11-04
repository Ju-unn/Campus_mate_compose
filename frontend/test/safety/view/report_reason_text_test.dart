import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/safety/model/data/report_reason.dart';
import 'package:campus_mate/safety/view/report_reason_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('신고 사유 글자는 서버 문구(운영자용)가 아니라 pen yl8gX 행 문구다(xarhn · AMxAh · w8qR7 · BHphm · YhPFL)', () {
    final l10n = AppLocalizationsKo();

    expect(ReportReason.values.map((reason) => reason.label(l10n)), [
      '욕설·비방·혐오',
      '성적 불쾌감',
      '광고·스팸',
      '사칭·허위',
      '기타',
    ]);
  });
}
