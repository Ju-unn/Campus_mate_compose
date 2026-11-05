import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/safety/view/contact_privacy_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsKo();
  const server = '고른 분의 전화번호만 원래 번호로 되돌릴 수 없는 형태로 바꿔 서버에 저장해요.';
  const notSent = '이름과 연락처 목록은 서버로 보내지 않아요.';
  const device = '이 기기에는 고른 분의 이름과 가린 번호만 저장돼요.';

  test('권한 안내(8a)는 서버 저장 문장과 목록은 안 보낸다는 문장을 공백 하나로 잇는다', () {
    expect(l10n.contactServerAndNotSent, '$server $notSent');
  });

  test('연락처 선택(8d) 바닥 안내는 서버 저장 문장과 이 기기 저장 문장을 잇는다', () {
    expect(l10n.contactServerAndDevice, '$server $device');
  });

  test('가입 마지막 소개(06-4)는 세 문장을 모두 잇는다', () {
    expect(l10n.contactAllNotices, '$server $notSent $device');
  });
}
