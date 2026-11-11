import 'package:campus_mate/consent/model/data/consent_item.dart';
import 'package:campus_mate/consent/view/consent_item_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('줄 글은 pen 02-c 그대로다 — 글자는 문구 파일(ARB)에서 온다', () {
    final l10n = AppLocalizationsKo();

    expect([for (final item in ConsentItem.values) item.label(l10n)], [
      '이용약관',
      '개인정보 수집·이용',
      '마케팅 활용 동의',
    ]);
  });
}
