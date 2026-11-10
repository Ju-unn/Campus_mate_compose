import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/basic/model/data/basic_info_submission.dart';
import 'package:campus_mate/profile/basic/model/data/phone_code_sent.dart';
import 'package:campus_mate/profile/basic/model/repository/basic_info_repository.dart';

class FakeBasicInfoRepository implements BasicInfoRepository {
  Result<bool> nextAvailabilityResult = const Success(true);
  Result<void> nextSubmitResult = const Success(null);
  final List<String> checkedNicknames = [];
  BasicInfoSubmission? submitted;

  /// 채워 두면 조회가 여기서 멈춘다 — "조회 중에 입력이 또 바뀌는" 상황을 테스트가 만들 때만 쓴다.
  Completer<void>? availabilityGate;

  @override
  Future<Result<bool>> checkNicknameAvailability(String nickname) async {
    checkedNicknames.add(nickname);
    await availabilityGate?.future;
    return nextAvailabilityResult;
  }

  /// 보낸 횟수 — 두 번 눌러도 한 번만 가는지 본다.
  int submitCount = 0;

  /// 채워 두면 보내기가 여기서 멈춘다 — "보내는 중" 화면을 테스트가 볼 때만 쓴다.
  Completer<void>? submitGate;

  @override
  Future<Result<void>> submit(BasicInfoSubmission submission) async {
    submitCount++;
    submitted = submission;
    await submitGate?.future;
    return nextSubmitResult;
  }

  /// 기본값은 서버가 새로 보낸 경우(다시 받기 60초 · 유효 3분).
  Result<PhoneCodeSent> nextSendResult = const Success(
    PhoneCodeSent(resendAfter: Duration(seconds: 60), expiresIn: Duration(seconds: 180), alreadySent: false),
  );
  Result<void> nextVerifyResult = const Success(null);

  /// 인증번호를 받은 번호(숫자만) · 확인한 (번호, 인증번호) — 몇 번 갔는지도 센다.
  final List<String> sentPhones = [];
  final List<(String, String)> verifiedCodes = [];

  /// 채워 두면 받기 · 확인이 여기서 멈춘다 — "보내는 중 ⑩ · 확인 중 ⑪" 을 테스트가 볼 때만 쓴다.
  Completer<void>? sendGate;
  Completer<void>? verifyGate;

  @override
  Future<Result<PhoneCodeSent>> sendPhoneCode(String phoneDigits) async {
    sentPhones.add(phoneDigits);
    await sendGate?.future;
    return nextSendResult;
  }

  @override
  Future<Result<void>> verifyPhoneCode(String phoneDigits, String code) async {
    verifiedCodes.add((phoneDigits, code));
    await verifyGate?.future;
    return nextVerifyResult;
  }
}
