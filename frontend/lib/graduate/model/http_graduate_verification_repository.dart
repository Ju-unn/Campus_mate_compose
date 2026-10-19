import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository.dart';
import 'package:campus_mate/graduate/model/previous_school_email.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';

/// [GraduateVerificationRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는 `sendAuthorizedRequest` 가 한다.
class HttpGraduateVerificationRepository implements GraduateVerificationRepository {
  const HttpGraduateVerificationRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> chooseMethod(VerificationMethod? method) => _api.send<void>(
        'PUT',
        '/me/verification-method',
        (_) {},
        body: {'method': method?.wire},
      );

  /// 사진이 있어 JSON 지름길([ApiClient.send])을 못 쓴다. `agreed` 는 신청 화면의 동의 줄을 누른 뒤에만 오므로 늘 `true`.
  @override
  Future<Result<GraduateRequestState>> submit(File photo, PreviousSchoolEmail? previousEmail) async {
    final fields = {'agreed': 'true', 'previous_school_email': ?previousEmail?.toRequestValue()};
    final result = await _api.sendMultipart('/graduate-verification', fields, photo.path);
    return result.when(
      onSuccess: (response) {
        // ApiClient.send 와 같은 이유 — 약속과 다른 본문의 캐스트 오류가 Result 밖으로 튀면 화면이 멈춘다.
        final state = _pendingOrNull(response.body);
        return state == null ? const FailureResult<GraduateRequestState>(UnknownFailure()) : Success(state);
      },
      onFailure: (failure) => FailureResult(failure),
    );
  }

  static GraduateRequestState? _pendingOrNull(String body) {
    try {
      final state = GraduateRequestState.tryParse(jsonDecode(body));
      return state is GraduatePending ? state : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<Result<GraduateRequestState?>> fetchState() => _api.send<GraduateRequestState?>(
        'GET',
        '/me/verification-status',
        (body) => GraduateRequestState.tryParse((body as Map<String, dynamic>)['graduate']),
      );
}
