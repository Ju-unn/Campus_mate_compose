import 'package:campus_mate/auth/gate/model/data/verification_gate.dart';
import 'package:campus_mate/auth/gate/model/repository/verification_gate_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/graduate/model/data/verification_method.dart';

/// [VerificationGateRepository]를 FastAPI 호출로 구현한다.
class HttpVerificationGateRepository implements VerificationGateRepository {
  const HttpVerificationGateRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<GateStatus>> fetchGate() => _api.send('GET', '/me/verification-status', (body) {
        final fields = body as Map<String, dynamic>;
        return (gate: VerificationGate.fromStatus(fields), method: VerificationMethod.tryParse(fields['verification_method']));
      });
}
