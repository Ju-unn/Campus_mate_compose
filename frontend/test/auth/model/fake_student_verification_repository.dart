import 'dart:io';

import 'package:campus_mate/auth/model/real_name.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [StudentVerificationRepository]. 기본은 제출·조회 모두 성공이고,
/// `nextSubmitResult`·`nextFetchStatusResult` 를 지정해 실패를 흉내 낼 수 있다.
class FakeStudentVerificationRepository implements StudentVerificationRepository {
  Result<VerificationOutcome> nextSubmitResult = const Success(VerificationOutcome(status: 'pending'));
  Result<VerificationOutcome> nextFetchStatusResult = const Success(VerificationOutcome(status: 'none'));

  /// 서버로 실제 제출이 갔는지 확인하는 용도(얼굴 미검출 시 비어 있어야 한다).
  final List<RealName> submittedRealNames = [];

  /// 어떤 파일이 올라갔는지 — 원본이 아니라 압축본이어야 한다(설계 §7.4).
  final List<File> submittedPhotos = [];

  @override
  Future<Result<VerificationOutcome>> submit(RealName realName, File photo) {
    submittedRealNames.add(realName);
    submittedPhotos.add(photo);
    // 실제 네트워크 호출처럼 마이크로태스크 이상의 지연을 흉내 내,
    // 위젯 테스트가 로딩 중 프레임을 pump() 로 관찰할 수 있게 한다.
    return Future.delayed(Duration.zero, () => nextSubmitResult);
  }

  @override
  Future<Result<VerificationOutcome>> fetchStatus() {
    return Future.delayed(Duration.zero, () => nextFetchStatusResult);
  }
}
