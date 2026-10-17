import 'package:campus_mate/billing/model/everytime_form_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 주소 글자는 everytime_form_link.dart 한 곳에만 둔다 — 여기서는 규칙만 본다(consent_links_test 와 같은 규칙).
  test('노션 공개 주소(notion.site) 페이지 맨 위다 — app.notion.com 은 기기 브라우저에서 로그인을 요구할 수 있다', () {
    expect((everytimeFormLink.scheme, everytimeFormLink.host), ('https', 'golden-leech-197.notion.site'));
    expect(everytimeFormLink.pathSegments, [matches(RegExp(r'^[0-9a-f]{32}$'))]);
    expect(everytimeFormLink.hasQuery, isFalse);
    expect(everytimeFormLink.hasFragment, isFalse);
  });
}
