import 'package:campus_mate/common/result.dart';

abstract interface class BioRepository {
  /// 06-2b 자기소개 AI 초안. 서버가 최초 1회만 만들어 준다(두 번째부터 409).
  Future<Result<String>> generateDraft();

  /// 06-3 자기소개 저장. 성공하면 온보딩이 끝나 프로필이 활성화된다.
  Future<Result<void>> submit(String bio);
}
