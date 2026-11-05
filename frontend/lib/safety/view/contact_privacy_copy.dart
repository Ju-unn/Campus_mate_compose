import 'package:campus_mate/l10n/app_localizations.dart';

// 지인 차단 개인정보 안내 문장 — 8a(`contact_permission_sheets.dart`) · 8d(`contact_picker_screen.dart`) ·
// 06-4(`onboarding_contact_block_screen.dart`)가 함께 쓴다. 문장은 문구 파일(ARB)의 safetyContact…Notice 세 개다.
// iOS `NSContactsUsageDescription`(Info.plist)도 같은 문장이다.
//
// 코드 사실에 맞춘다(2026-10-14 사용자 결정 "연락처 안내 문구 정정"):
// - 서버로는 8d 에서 고른 사람의 번호만 간다(`contact_block_repository.dart` add). 이름 · 연락처 전체는 안 간다.
// - 서버는 번호를 되돌릴 수 없는 해시(HMAC-SHA256)로만 저장한다(`backend/app/safety/router.py` add_contact_blocks).
//   '암호화' 는 풀 수 있는 변환이라 사실과 다르다 — 쓰지 않는다.
// - 이 기기에는 고른 사람의 이름과 가린 번호(010-****-1234)만 남는다(`contact_name_store.dart`).
// 사실이 바뀌면 이 문장과 Info.plist, 개인정보처리방침을 같이 고친다.

/// 세 문장을 화면마다 다른 조합으로 이어 붙인다(사이는 공백 하나).
extension ContactPrivacyCopy on AppLocalizations {
  /// 8a 권한 안내: 서버 저장 + 목록은 안 보냄.
  String get contactServerAndNotSent => '$safetyContactServerNotice $safetyContactNotSentNotice';

  /// 8d 바닥 안내: 서버 저장 + 이 기기 저장.
  String get contactServerAndDevice => '$safetyContactServerNotice $safetyContactDeviceNotice';

  /// 06-4 소개: 셋 모두.
  String get contactAllNotices => '$safetyContactServerNotice $safetyContactNotSentNotice $safetyContactDeviceNotice';
}
