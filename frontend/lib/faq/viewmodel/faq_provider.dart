import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 21 과 설정 "자주 묻는 질문" 줄이 함께 본다. 받으면 캐시에 쓰고, 못 받으면 마지막 캐시, 그것도 없으면 빈 목록 —
/// 빈 목록이면 설정 줄이 숨는다(DESIGN §8.13 "빈 상태 없음").
// ponytail: 앱을 켠 동안 한 번만 받는다(autoDispose 아님). 운영에서 고친 문구는 다음 실행 때 보인다 — 더 빨라야 하면 21 을 열 때 invalidate.
final faqProvider = FutureProvider<List<FaqItem>>((ref) async {
  final cache = ref.read(faqCacheProvider);
  final result = await ref.read(faqRepositoryProvider).fetchAll();
  return result.when(
    onSuccess: (items) async {
      try {
        await cache.save(items);
      } on Object {
        // 캐시는 덤이다 — 못 써도 받은 목록은 보여 준다.
      }
      return items;
    },
    onFailure: (_) => cache.load(),
  );
});
