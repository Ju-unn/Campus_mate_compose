import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 화면 21 의 문구(`faq` 표).
abstract interface class FaqRepository {
  Future<Result<List<FaqItem>>> fetchAll();
}

/// FastAPI 를 거치지 않고 Supabase 에서 바로 읽는다. `faq` 는 ERD §2 에서 authenticated 전체 읽기인
/// 공개 참조 표다(ERD_DECISIONS 8 의 예외 4개 중 하나) — 개인정보도 남의 데이터도 없다.
class SupabaseFaqRepository implements FaqRepository {
  const SupabaseFaqRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Result<List<FaqItem>>> fetchAll() async {
    try {
      final rows = await _client.from('faq').select('id, category, question, answer, sort_order').order('sort_order');
      return Success(parseFaqRows(rows));
    } on Object {
      // 이유는 가르지 않는다 — 부르는 쪽은 어떤 실패든 캐시로 넘어간다. 깨진 행의 형 변환 오류(Error)도 여기서 잡는다 —
      // 새면 faqProvider 가 오류가 되어 21 이 스피너에 멈춘다.
      return const FailureResult(NetworkFailure());
    }
  }
}

final faqRepositoryProvider = Provider<FaqRepository>((ref) => SupabaseFaqRepository(Supabase.instance.client));
