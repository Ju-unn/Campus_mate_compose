import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/previous_school_email.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';

/// 졸업생 인증(졸업증명서) 길의 서버 호출.
abstract interface class GraduateVerificationRepository {
  /// `PUT /me/verification-method`. [method] 가 null 이면 서버 값을 비운다(뒤로가기 — 방법 고르기로 돌아간다).
  Future<Result<void>> chooseMethod(VerificationMethod? method);

  /// `POST /graduate-verification`(multipart). 성공하면 심사 중 상태. 429 는 [RateLimitedFailure](신청 횟수 소진),
  /// 그 밖의 거절은 서버 `code` 를 단 `ServerRejectedFailure` 다.
  Future<Result<GraduateRequestState>> submit(File photo, PreviousSchoolEmail? previousEmail);

  /// `GET /me/verification-status` 의 `graduate` 칸만 읽는다. 신청이 없거나 칸이 없으면(옛 서버) null.
  /// 관문 판정은 [VerificationGateRepository] 가 따로 한다 — 이것은 반려 사유 · 남은 횟수를 화면에 보이려는 읽기다.
  Future<Result<GraduateRequestState?>> fetchState();
}
