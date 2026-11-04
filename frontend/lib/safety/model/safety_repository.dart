import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/blocked_user.dart';
import 'package:campus_mate/safety/model/partner_profile.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/report_target.dart';

/// 조각 6 신고 · 차단 서버 호출. 둘이 늘 함께 움직여(신고하면 차단된다, 결정 4) 인터페이스 하나로 둔다.
abstract interface class SafetyRepository {
  /// [note] 는 [ReportReason.other] 일 때만 서버로 간다. 사유를 바꿔도 화면이 메모를 비울 필요가 없다.
  Future<Result<void>> report({
    required ReportTarget target,
    required ReportReason reason,
    String? note,
  });

  /// 이미 차단돼 있어도 성공이다(서버가 200) — 재시도해도 안전하다.
  Future<Result<void>> block(String profileId);

  /// 최신 차단이 먼저 온다.
  Future<Result<List<BlockedUser>>> fetchBlocks();

  /// 해제해도 대화는 돌아오지 않는다(16f 문구). 이미 없는 행이어도 성공이다.
  Future<Result<void>> unblock(String profileId);

  /// 14c 상대 프로필. 차단 · 나감 · 탈퇴는 모두 같은 404 로 온다(차단 사실이 새지 않게).
  Future<Result<PartnerProfile>> fetchPartnerProfile(String profileId);
}
