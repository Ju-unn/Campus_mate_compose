/// 빌드 시점 환경 값. `--dart-define`으로만 주입하고 코드에 리터럴로 남기지 않는다.
abstract final class Env {
  /// FastAPI 백엔드 기본 URL (`--dart-define=API_BASE_URL=...`).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// 앱 스토어 리뷰 페이지 주소 (`--dart-define=STORE_REVIEW_URL=...`). 비어 있는 동안 홈의 "리뷰 남기기" 는 "곧 열려요" 만 보여 준다.
  static const storeReviewUrl = String.fromEnvironment('STORE_REVIEW_URL');
}
