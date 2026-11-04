import 'package:campus_mate/l10n/app_localizations_ko.dart';

/// 공유 글(19 결정 5). 하트 숫자 · 스토어 링크는 넣지 않는다.
/// 카카오톡 공유가 안 될 때도 이 글을 그대로 보낸다 — "추천 코드 {코드}" 모양에 친구 코드 리뷰 붙여넣기가 기댄다(friend_code_screen).
///
/// 한국어 고정 껍데기다 — 저장소 provider 에는 `BuildContext` 가 없어 `AppLocalizationsKo()` 로 읽는다. 언어를 늘릴 때 view 가
/// `context.l10n.referralShareText(code: …)` 로 글을 만들어 넘기게 바꾼다(B8 마무리에서 지운다).
String inviteShareText(String code) => AppLocalizationsKo().referralShareText(code: code);

/// 카카오톡 공유 카드의 사용자 정의 템플릿 번호(카카오 디벨로퍼스 [도구] > [메시지 템플릿], 계획서 3-8).
/// 138148 = 카카오 빌더에서 만든 추천 코드 공유 템플릿(사용자 확인 10-19). 제목 `CampusMate 추천 코드 ${code}`, 버튼 앱 실행 파라미터 `ref=${code}` 전제.
/// 시험이 null 로 갈아 끼우면 카카오를 부르지 않고 기기 공유 창으로 간다.
const int kakaoInviteTemplateId = 138148;
