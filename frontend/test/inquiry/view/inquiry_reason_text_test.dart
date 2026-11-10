import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/view/inquiry_reason_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('문의 사유 글자는 서버 문구(운영자용 "계정·인증")가 아니라 pen 21b 행 문구다(zEIEr · s5azT1 · d8rBt · tYsNG · azPoP · i1R84)', () {
    final l10n = AppLocalizationsKo();

    expect(InquiryReason.values.map((reason) => reason.label(l10n)), [
      '계정 · 인증',
      '결제 · 하트',
      '매칭 · 카드',
      '신고 · 안전',
      '앱 오류',
      '기타',
    ]);
  });
}
