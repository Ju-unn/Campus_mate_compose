/// 빌드 시점 환경 값. `--dart-define`으로만 주입하고 코드에 리터럴로 남기지 않는다.
abstract final class Env {
  /// FastAPI 백엔드 기본 URL (`--dart-define=API_BASE_URL=...`).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
}
