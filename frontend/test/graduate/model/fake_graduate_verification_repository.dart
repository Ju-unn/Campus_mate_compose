import 'dart:async';
import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository.dart';
import 'package:campus_mate/graduate/model/previous_school_email.dart';
import 'package:campus_mate/graduate/model/verification_method.dart';

/// ViewModel · 화면 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼우고, 받은 호출을 장부에 적는다.
class FakeGraduateVerificationRepository implements GraduateVerificationRepository {
  Result<void> chooseResult = const Success(null);
  Result<GraduateRequestState> submitResult = const Success(GraduatePending(attemptsLeft: 2));
  Result<GraduateRequestState?> stateResult = const Success(null);

  /// `chooseMethod` 에 받은 값 — 뒤로가기는 null 이 적힌다.
  final List<VerificationMethod?> chosen = [];
  final List<(String, String?)> submitted = [];
  int fetchStateCount = 0;

  /// 채워 두면 `chooseMethod` 가 이것이 끝날 때까지 멈춘다 — 보내는 중에 한 번 더 누르는 상황용.
  Completer<void>? holdChoose;
  Completer<void>? holdSubmit;
  Completer<void>? holdFetchState;

  @override
  Future<Result<void>> chooseMethod(VerificationMethod? method) async {
    chosen.add(method);
    await holdChoose?.future;
    return chooseResult;
  }

  @override
  Future<Result<GraduateRequestState>> submit(File photo, PreviousSchoolEmail? previousEmail) async {
    submitted.add((photo.path, previousEmail?.toRequestValue()));
    await holdSubmit?.future;
    return submitResult;
  }

  @override
  Future<Result<GraduateRequestState?>> fetchState() async {
    fetchStateCount++;
    await holdFetchState?.future;
    return stateResult;
  }
}
