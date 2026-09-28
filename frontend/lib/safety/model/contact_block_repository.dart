import 'dart:math';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 서버 한 번에 받는 번호 수(`backend/app/safety/reasons.py` CONTACT_BLOCK_BATCH_MAX 와 같아야 한다).
/// 넘기면 422 라서 저장소가 나눠 보낸다.
const int contactBlockBatchMax = 200;

/// 서버가 아는 지인 차단 한 건. 이름 · 번호는 없다 — 이름은 기기 파일(`ContactNameStore`)에만 있다.
class ContactBlock {
  const ContactBlock({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}

/// 지인 차단(`/contact-blocks`). 번호 원문은 [add] 의 요청 본문에만 실린다.
abstract interface class ContactBlockRepository {
  /// 입력과 같은 길이 · 같은 순서로 차단 id 를 돌려준다. 휴대전화가 아닌 자리는 null.
  Future<Result<List<String?>>> add(List<String> numbers);

  /// 최신순.
  Future<Result<List<ContactBlock>>> fetch();

  Future<Result<void>> remove(String blockId);
}

class HttpContactBlockRepository implements ContactBlockRepository {
  const HttpContactBlockRepository(this._api);

  final ApiClient _api;

  /// 앞 배치가 저장된 뒤 뒤 배치가 실패하면 실패를 돌려준다 — 다시 보내도 서버가 같은 id 를 돌려줘(upsert)
  /// 그때 이름이 짝지어진다.
  @override
  Future<Result<List<String?>>> add(List<String> numbers) async {
    final ids = <String?>[];
    for (var start = 0; start < numbers.length; start += contactBlockBatchMax) {
      final batch = numbers.sublist(start, min(start + contactBlockBatchMax, numbers.length));
      final result = await _api.send('POST', '/contact-blocks', _toIds, body: {'numbers': batch});
      final failure = result.when<Failure?>(
        onSuccess: (batchIds) {
          ids.addAll(batchIds);
          return null;
        },
        onFailure: (failure) => failure,
      );
      if (failure != null) return FailureResult(failure);
    }
    return Success(ids);
  }

  /// `{"blocks": [{"id", "created_at"} | null, ...]}` 에서 id 만 순서대로 꺼낸다.
  static List<String?> _toIds(Object body) => [
        for (final item in _blocks(body)) item == null ? null : (item as Map<String, dynamic>)['id'] as String,
      ];

  static List<dynamic> _blocks(Object body) => (body as Map<String, dynamic>)['blocks'] as List<dynamic>;

  @override
  Future<Result<List<ContactBlock>>> fetch() => _api.send(
        'GET',
        '/contact-blocks',
        (body) => [
          for (final item in _blocks(body).cast<Map<String, dynamic>>())
            ContactBlock(
              id: item['id'] as String,
              createdAt: DateTime.parse(item['created_at'] as String).toLocal(),
            ),
        ],
      );

  @override
  Future<Result<void>> remove(String blockId) => _api.send('DELETE', '/contact-blocks/$blockId', (_) {});
}

final contactBlockRepositoryProvider = Provider<ContactBlockRepository>(
  (ref) => HttpContactBlockRepository(ref.read(apiClientProvider)),
);
