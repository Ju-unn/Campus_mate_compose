import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/common/result.dart';

/// 3b 화면의 제출 결과.
/// 서버 응답을 그대로 옮기는 DTO라 원칙 7(인스턴스 변수 2개 이하) 예외로 취급한다.
class VerificationOutcome {
  const VerificationOutcome({required this.status, this.rejectReason});

  final String status; // 'pending' | 'verified' | 'rejected'
  final String? rejectReason;
}

abstract interface class StudentVerificationRepository {
  Future<Result<VerificationOutcome>> submit(RealName realName, File photo);
  Future<Result<VerificationOutcome>> fetchStatus();
}
