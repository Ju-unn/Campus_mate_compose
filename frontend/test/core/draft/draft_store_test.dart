import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기본 저장소는 아무것도 남기지 않는다 — main.dart 가 진짜 저장소로 바꿔 끼운다', () async {
    // 시험 · 통합 시험 하네스처럼 바꿔 끼우지 않은 자리에서는 예전처럼 메모리에만 들고 있다.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final drafts = container.read(draftStoreProvider);

    drafts.write(DraftScreen.idealNote, {'note': '남지 않는다'});

    expect(drafts, isA<NoDraftStore>());
    expect(drafts.read(DraftScreen.idealNote, (data) => data), isNull);
    await expectLater(drafts.clear(DraftScreen.idealNote), completes);
    await expectLater(drafts.clearAll(), completes);
  });
}
