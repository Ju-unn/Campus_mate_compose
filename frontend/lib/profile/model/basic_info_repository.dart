import 'package:campus_mate/common/result.dart';

/// 04-1 기본 정보 제출값. 개별 필드로 넘기면 인자 순서 실수가 나기 쉬워 값 객체로 묶는다.
class BasicInfoSubmission {
  const BasicInfoSubmission({
    required this.nickname,
    required this.birthYear,
    required this.heightCm,
    required this.phoneNumber,
    required this.gender,
    this.mbti,
  });

  final String nickname;
  final int birthYear;
  final int heightCm;
  final String phoneNumber;
  final String gender;
  final String? mbti;
}

abstract interface class BasicInfoRepository {
  Future<Result<bool>> checkNicknameAvailability(String nickname);
  Future<Result<void>> submit(BasicInfoSubmission submission);
}
