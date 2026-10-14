/// 노션 공개 주소(notion.site). 옛 app.notion.com 주소는 기기 브라우저에서 로그인 요구가 뜰 수 있어
/// 10-14 노션 재구성 때 모든 링크를 공개 주소로 통일했다(대장 지시). 페이지 id · 주소는 재구성 전과 같다.
const _site = 'https://golden-leech-197.notion.site';

/// "약관동의" 페이지 — I. 서비스 이용약관 · II. 유료 서비스 약관. 개인정보 처리방침은 10-14 에 별도 페이지로 나갔다.
const _termsPage = '$_site/3e9d998f0dee8082be84e126630b02a7';

/// "개인정보 처리방침" 페이지(방침의 단일 원본).
const _privacyPage = '$_site/3ead998f0dee80d08709d6b75c79ddc0';

/// 이용약관(02-c "보기" · 설정 16 "이용약관" 줄). I 부가 페이지 맨 위라 앵커가 없다.
final Uri termsLink = Uri.parse(_termsPage);

/// 02-c "개인정보 수집·이용" 보기. 종교(민감정보) 동의도 이 줄이 받는다(09-29).
/// **한계**: 앵커가 없어 방침 맨 위가 열린다 — "처리하는 개인정보 항목"과 종교 문단은 사용자가 페이지 안에서 찾아 내려가야 한다.
/// 그 항의 블록 링크를 받으면 `'$_privacyPage#<블록 id>'` 로 바꾼다.
final Uri privacyItemsLink = Uri.parse(_privacyPage);

/// 설정 16 "개인정보처리방침" 줄(A6). 방침 페이지 맨 위.
final Uri privacyPolicyLink = Uri.parse(_privacyPage);

/// 하트 구매 결제 안내(pen `bBjRD` "유료 서비스 약관 ›"). 유료 서비스 약관은 약관동의 페이지 II 부다.
/// 앵커는 노션 블록 id 라 아직 모른다 — 지금은 페이지 맨 위(I 부)가 열린다.
/// 노션 교체 뒤 II 부 블록 링크를 받으면 `'$_termsPage#<블록 id>'` 로 앵커를 더할 수 있다.
final Uri paidServiceTermsLink = Uri.parse(_termsPage);
