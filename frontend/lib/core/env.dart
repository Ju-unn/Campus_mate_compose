/// 빌드 시점 환경 값. `--dart-define`으로만 주입하고 코드에 리터럴로 남기지 않는다.
abstract final class Env {
  /// FastAPI 백엔드 기본 URL (`--dart-define=API_BASE_URL=...`).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// 앱 스토어 리뷰 페이지 주소 (`--dart-define=STORE_REVIEW_URL=...`). 비어 있는 동안 홈의 "리뷰 남기기" 는 "곧 열려요" 만 보여 준다.
  static const storeReviewUrl = String.fromEnvironment('STORE_REVIEW_URL');

  /// 카카오 네이티브 앱 키 (`--dart-define=KAKAO_NATIVE_APP_KEY=...`). 비어 있으면 `KakaoSdk.init` 을 건너뛰고 카카오 버튼은 실패 토스트.
  /// 안드로이드 복귀 스킴(`kakao{키}://oauth`)은 같은 이름의 gradle 값으로 따로 넣는다(`android/app/build.gradle.kts`).
  static const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  /// 구글 **웹** 클라이언트 ID (`--dart-define=GOOGLE_WEB_CLIENT_ID=...`). Supabase 가 ID 토큰의 aud 로 확인한다.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
}
