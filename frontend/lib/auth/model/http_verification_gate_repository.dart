import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [VerificationGateRepository]를 FastAPI 호출로 구현한다.
class HttpVerificationGateRepository implements VerificationGateRepository {
  const HttpVerificationGateRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<VerificationGate>> fetchGate() =>
      _api.send('GET', '/me/verification-status', (body) => VerificationGate.fromStatus(body as Map<String, dynamic>));
}
