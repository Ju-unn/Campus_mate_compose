import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/result.dart';

abstract interface class VerificationGateRepository {
  Future<Result<VerificationGate>> fetchGate();
}
