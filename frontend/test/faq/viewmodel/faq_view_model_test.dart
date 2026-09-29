import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:campus_mate/faq/viewmodel/faq_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_faq.dart';

void main() {
  group('faqSections', () {
    test('검색어가 없으면 고른 탭 묶음 하나만, sort_order 순', () {
      final sections = faqSections(faqFixture, const FaqUiState());
      expect(sections.single.category, FaqCategory.cardMatching);
      expect(sections.single.items.map((i) => i.id), ['c1', 'c2']);

      final account = faqSections(faqFixture, const FaqUiState(selected: FaqCategory.account));
      expect(account.single.items.map((i) => i.id), ['a1', 'a2']);
    });

    test('검색 중에는 탭과 상관없이 전 묶음을 enum 순서로 찾는다', () {
      final sections = faqSections(faqFixture, const FaqUiState(query: '요', selected: FaqCategory.account));
      expect(sections.map((s) => s.category), FaqCategory.values);
      expect(sections.first.items.map((i) => i.id), ['c1', 'c2']);
    });

    test('답변에만 있는 말로도 찾고, 걸린 게 없는 묶음은 뺀다', () {
      // f1 은 답변("신고할 수 있어요.")에만, s1 은 질문에 있다.
      final sections = faqSections(faqFixture, const FaqUiState(query: '신고'));
      expect(sections.map((s) => s.category), [FaqCategory.friendReview, FaqCategory.safety]);
    });

    test('앞뒤 공백은 깎고, 공백뿐이면 탭 모습, 아무것도 안 걸리면 빈 목록', () {
      expect(faqSections(faqFixture, const FaqUiState(query: '  하트  ')).single.items.single.id, 'h1');
      expect(faqSections(faqFixture, const FaqUiState(query: '   ')).single.category, FaqCategory.cardMatching);
      expect(faqSections(faqFixture, const FaqUiState(query: '없는말')), isEmpty);
    });

    test('영문은 대소문자를 가리지 않는다', () {
      const item = FaqItem(id: 'm', category: FaqCategory.account, question: 'MBTI 를 바꿀 수 있나요?', answer: '네', sortOrder: 1);
      expect(faqSections([item], const FaqUiState(query: 'mbti')), hasLength(1));
    });
  });

  group('FaqViewModel', () {
    late ProviderSubscription<FaqUiState> sub;
    late FaqViewModel vm;

    setUp(() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      sub = container.listen(faqViewModelProvider, (_, _) {});
      vm = container.read(faqViewModelProvider.notifier);
    });

    test('처음은 카드·매칭 탭, 검색어 · 펼침 없음', () {
      expect(sub.read().selected, FaqCategory.cardMatching);
      expect(sub.read().query, '');
      expect(sub.read().expandedId, isNull);
      expect(sub.read().searching, isFalse);
    });

    test('한 번에 하나만 펼치고, 펼친 걸 다시 누르면 접는다', () {
      vm.toggle('c1');
      expect(sub.read().expandedId, 'c1');
      vm.toggle('c2');
      expect(sub.read().expandedId, 'c2');
      vm.toggle('c2');
      expect(sub.read().expandedId, isNull);
    });

    test('탭을 바꾸면 펼친 답은 접힌다(대장 09-29)', () {
      vm.toggle('c1');
      vm.selectTab(FaqCategory.safety);
      expect(sub.read().selected, FaqCategory.safety);
      expect(sub.read().expandedId, isNull);
    });

    test('검색어를 지우면 고른 탭으로 돌아가고, 검색어를 바꿔도 펼친 줄은 그대로다', () {
      vm.selectTab(FaqCategory.safety);
      vm.toggle('s1');
      vm.search('신고');
      expect(sub.read().searching, isTrue);
      expect(sub.read().expandedId, 's1');

      vm.search('');
      expect(sub.read().searching, isFalse);
      expect(sub.read().selected, FaqCategory.safety);
    });
  });
}
