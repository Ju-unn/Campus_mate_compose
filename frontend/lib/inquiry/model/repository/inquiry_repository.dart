import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';

/// 문의하기 서버 호출(`POST /inquiries`). 서버는 로그인만 확인하므로 정지된 사람 · 가입 중인 사람도 보낼 수 있다.
abstract interface class InquiryRepository {
  /// 실패: 429 하루 5건 상한은 `RateLimitedFailure`, 연결 문제는 `NetworkFailure`, 탈퇴한 계정은 `WithdrawnFailure`.
  Future<Result<void>> send({
    required InquiryReason reason,
    required String body,
    required String replyEmail,
  });
}
