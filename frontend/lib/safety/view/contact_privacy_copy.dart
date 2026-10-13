// 지인 차단 개인정보 안내 문장 — 8a(`contact_permission_sheets.dart`) · 8d(`contact_picker_screen.dart`) ·
// 06-4(`onboarding_contact_block_screen.dart`)가 함께 쓴다. iOS `NSContactsUsageDescription`(Info.plist)도 같은 문장이다.
//
// 코드 사실에 맞춘다(2026-10-14 사용자 결정 "연락처 안내 문구 정정"):
// - 서버로는 8d 에서 고른 사람의 번호만 간다(`contact_block_repository.dart` add). 이름 · 연락처 전체는 안 간다.
// - 서버는 번호를 되돌릴 수 없는 해시(HMAC-SHA256)로만 저장한다(`backend/app/safety/router.py` add_contact_blocks).
//   '암호화' 는 풀 수 있는 변환이라 사실과 다르다 — 쓰지 않는다.
// - 이 기기에는 고른 사람의 이름과 가린 번호(010-****-1234)만 남는다(`contact_name_store.dart`).
// 사실이 바뀌면 이 문장과 Info.plist, 개인정보처리방침을 같이 고친다.

const String contactServerNotice = '고른 분의 전화번호만 원래 번호로 되돌릴 수 없는 형태로 바꿔 서버에 저장해요.';
const String contactNotSentNotice = '이름과 연락처 목록은 서버로 보내지 않아요.';
const String contactDeviceNotice = '이 기기에는 고른 분의 이름과 가린 번호만 저장돼요.';
