import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:campus_mate/faq/viewmodel/faq_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_faq.dart';

void main() {
  ProviderContainer containerWith(FakeFaqRepository repository, FakeFaqCache cache) {
    final container = ProviderContainer(
      overrides: [
        faqRepositoryProvider.overrideWithValue(repository),
        faqCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('받으면 그 목록을 주고 캐시에 쓴다', () async {
    final cache = FakeFaqCache();
    final container = containerWith(FakeFaqRepository(const Success(faqFixture)), cache);
    expect(await container.read(faqProvider.future), faqFixture);
    expect(cache.saved, faqFixture);
  });

  test('못 받으면 캐시를 준다', () async {
    final container = containerWith(
      FakeFaqRepository(const FailureResult(NetworkFailure())),
      FakeFaqCache(stored: faqFixture.take(2).toList()),
    );
    expect((await container.read(faqProvider.future)).map((i) => i.id), ['c2', 'c1']);
  });

  test('못 받고 캐시도 없으면 빈 목록', () async {
    final container = containerWith(FakeFaqRepository(const FailureResult(NetworkFailure())), FakeFaqCache());
    expect(await container.read(faqProvider.future), isEmpty);
  });

  test('저장이 실패해도 받은 목록을 준다', () async {
    final container = containerWith(FakeFaqRepository(const Success(faqFixture)), FakeFaqCache(failSave: true));
    expect(await container.read(faqProvider.future), faqFixture);
  });
}
