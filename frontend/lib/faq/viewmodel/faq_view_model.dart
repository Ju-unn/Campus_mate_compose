import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 21 한 절 — 묶음과 그 아래 문항들.
typedef FaqSection = ({FaqCategory category, List<FaqItem> items});

/// 평소에는 고른 탭 묶음 하나(pen `Sg89A`). 검색어가 있으면 탭과 상관없이 전 묶음에서 찾는다(사용자 결정 ① 가, 09-29) —
/// 앞뒤 공백을 깎고 질문 · 답변을 부분일치로(DESIGN §8.13 "단순 부분일치면 충분하다"), 걸린 게 없는 묶음은 뺀다.
/// 묶음은 enum 순서, 묶음 안은 sort_order 순.
List<FaqSection> faqSections(List<FaqItem> items, FaqUiState ui) {
  final needle = ui.query.trim().toLowerCase();
  bool hit(FaqItem item) =>
      item.question.toLowerCase().contains(needle) || item.answer.toLowerCase().contains(needle);
  List<FaqItem> sorted(Iterable<FaqItem> found) => found.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (!ui.searching) {
    return [(category: ui.selected, items: sorted(items.where((i) => i.category == ui.selected)))];
  }
  return [
    for (final category in FaqCategory.values)
      if (sorted(items.where((i) => i.category == category && hit(i))) case final found when found.isNotEmpty)
        (category: category, items: found),
  ];
}

/// 21 의 검색어 · 고른 탭 · 펼친 문항.
class FaqUiState {
  const FaqUiState({this.query = '', this.selected = FaqCategory.cardMatching, this.expandedId});

  final String query;
  final FaqCategory selected;
  final String? expandedId;

  bool get searching => query.trim().isNotEmpty;
}

final faqViewModelProvider = NotifierProvider.autoDispose<FaqViewModel, FaqUiState>(FaqViewModel.new);

class FaqViewModel extends Notifier<FaqUiState> {
  @override
  FaqUiState build() => const FaqUiState();

  /// 검색어를 지우면 고른 탭으로 돌아간다 — 탭은 검색 중에도 기억한다.
  void search(String query) =>
      state = FaqUiState(query: query, selected: state.selected, expandedId: state.expandedId);

  /// 탭을 바꾸면 펼친 답은 접는다(대장 09-29).
  void selectTab(FaqCategory category) => state = FaqUiState(query: state.query, selected: category);

  /// 한 번에 하나만 펼친다(DESIGN §8.13 — 여러 개가 열리면 스크롤 위치를 잃는다). 펼친 걸 다시 누르면 접는다.
  void toggle(String id) => state = FaqUiState(
    query: state.query,
    selected: state.selected,
    expandedId: state.expandedId == id ? null : id,
  );
}
