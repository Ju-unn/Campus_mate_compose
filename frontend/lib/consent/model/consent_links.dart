/// 노션 "약관동의" 한 페이지(1부 이용약관 · 2부 개인정보 처리방침). 비로그인 공개(대장 확인 2026-09-29).
/// 실기기에서 로그인 요구가 뜨면 [_page] 를 notion.site 주소
/// (https://golden-leech-197.notion.site/3e9d998f0dee8082be84e126630b02a7)로 바꾼다.
/// 약관 페이지를 통째로 다시 쓰면 블록 id 가 바뀔 수 있다 — 앵커 재확인.
const _page = 'https://app.notion.com/p/3e9d998f0dee8082be84e126630b02a7';

/// 1부 이용약관.
final Uri termsLink = Uri.parse('$_page#792b6855eaa04bf8a24c19c86702d62f');

/// 2부 2항 "처리하는 개인정보 항목". 종교(민감정보) 문단도 이 항 끝에 있다 — 종교 동의도 이 줄이 받는다(09-29).
final Uri privacyItemsLink = Uri.parse('$_page#efcc38385bef4185b6577d663ebd3bc8');

/// 설정 16 "개인정보처리방침" 줄(A6). 2부 첫 블록 앵커를 받기 전까지 페이지 맨 위(1부 · 2부가 다 보인다, 대장 10-03 나).
final Uri privacyPolicyLink = Uri.parse(_page);
