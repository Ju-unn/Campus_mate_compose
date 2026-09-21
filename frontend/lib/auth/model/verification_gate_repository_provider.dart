import 'package:campus_mate/auth/model/http_verification_gate_repository.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FastAPI 기본 URL은 `Env.apiBaseUrl`(`--dart-define=API_BASE_URL=...`)에서 읽는다.
final verificationGateRepositoryProvider = Provider<VerificationGateRepository>((ref) {
  return HttpVerificationGateRepository(ref.read(apiClientProvider));
});
