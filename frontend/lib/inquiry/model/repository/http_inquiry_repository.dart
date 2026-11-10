import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_repository.dart';

/// [InquiryRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는 `ApiClient` 몫이라 여기서는 URL · 바디만 맡는다.
/// 성공 응답(`{"ok": true, "id": …}`)은 읽을 것이 없다.
class HttpInquiryRepository implements InquiryRepository {
  const HttpInquiryRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> send({
    required InquiryReason reason,
    required String body,
    required String replyEmail,
  }) =>
      _api.send('POST', '/inquiries', (_) {}, body: {
        'reason': reason.wire,
        'body': body,
        'reply_email': replyEmail,
      });
}
