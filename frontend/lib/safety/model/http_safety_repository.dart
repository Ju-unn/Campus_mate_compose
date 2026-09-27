import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/safety/model/partner_profile.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';

/// [SafetyRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는 `sendAuthorizedRequest` 몫이라
/// 여기서는 URL · 바디 · 파싱만 맡는다. 성공 응답은 `{"ok": true}` 뿐이라 읽을 것이 없다.
class HttpSafetyRepository implements SafetyRepository {
  const HttpSafetyRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> report({
    required ReportTarget target,
    required ReportReason reason,
    String? note,
  }) =>
      _api.send('POST', '/reports', (_) {}, body: {
        ...target.toJson(),
        'reason': reason.wire,
        'reason_note': ?_noteFor(reason, note),
      });

  /// 메모는 기타일 때만, 다듬어서 비어 있지 않을 때만 싣는다. 다른 사유면 서버가 어차피 버리지만,
  /// 기타에서 쓰다 사유를 바꾼 글이 신고 기록 옆으로 새어 나갈 이유가 없다.
  String? _noteFor(ReportReason reason, String? note) {
    final trimmed = note?.trim() ?? '';
    return reason == ReportReason.other && trimmed.isNotEmpty ? trimmed : null;
  }

  @override
  Future<Result<void>> block(String profileId) =>
      _api.send('POST', '/blocks/$profileId', (_) {});

  @override
  Future<Result<List<BlockedUser>>> fetchBlocks() => _api.send(
        'GET',
        '/blocks',
        (body) => ((body as Map<String, dynamic>)['blocks'] as List<dynamic>)
            .map((item) => BlockedUser.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  @override
  Future<Result<void>> unblock(String profileId) =>
      _api.send('DELETE', '/blocks/$profileId', (_) {});

  @override
  Future<Result<PartnerProfile>> fetchPartnerProfile(String profileId) => _api.send(
        'GET',
        '/profiles/$profileId',
        (body) => PartnerProfile.fromJson(body as Map<String, dynamic>),
      );
}
