import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [StudentVerificationRepository]를 FastAPI 호출로 구현한다.
class HttpStudentVerificationRepository implements StudentVerificationRepository {
  const HttpStudentVerificationRepository(this._api);

  final ApiClient _api;

  /// 학생증 사진은 multipart 라 JSON 지름길([ApiClient.send])을 쓰지 못한다.
  @override
  Future<Result<VerificationOutcome>> submit(RealName realName, File photo) async {
    final result = await _api.sendMultipart(
      '/student-verification',
      {'real_name': realName.toRequestValue()},
      photo.path,
    );
    return result.when(
      onSuccess: (response) => Success(_toOutcome(jsonDecode(response.body))),
      onFailure: (failure) => FailureResult(failure),
    );
  }

  @override
  Future<Result<VerificationOutcome>> fetchStatus() =>
      _api.send('GET', '/me/verification-status', _toOutcome);

  VerificationOutcome _toOutcome(Object body) {
    final fields = body as Map<String, dynamic>;
    return VerificationOutcome(
      status: fields['status'] as String,
      rejectReason: fields['reject_reason'] as String?,
    );
  }
}
