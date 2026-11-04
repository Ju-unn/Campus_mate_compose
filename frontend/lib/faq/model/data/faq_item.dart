/// FAQ 묶음(ERD `faq_category`). 화면 21 의 탭이 이 순서다(DESIGN §8.13 · pen `Sg89A`).
enum FaqCategory {
  cardMatching('card_matching'),
  heartPayment('heart_payment'),
  photoProfile('photo_profile'),
  friendReview('friend_review'),
  safety('safety'),
  account('account');

  const FaqCategory(this.wire);

  /// 표에 적힌 값. 탭 · 묶음 제목 글자는 view 의 `FaqCategoryText.label` 이 정한다(문구 파일 ARB).
  final String wire;
}

/// `faq` 한 줄.
class FaqItem {
  const FaqItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    required this.sortOrder,
  });

  final String id;
  final FaqCategory category;
  final String question;
  final String answer;
  final int sortOrder;

  /// 캐시 파일 한 줄 — [parseFaqRows] 가 표 행과 같은 모양으로 다시 읽는다.
  Map<String, Object> toJson() =>
      {'id': id, 'category': category.wire, 'question': question, 'answer': answer, 'sort_order': sortOrder};
}

/// 표 행이나 캐시 파일을 읽는다. 앱이 모르는 묶음(대시보드에서 enum 을 먼저 늘린 경우)은 버린다 —
/// 새 앱이 나오기 전까지 그 묶음만 안 보이고 나머지는 그대로 그린다.
List<FaqItem> parseFaqRows(List<dynamic> rows) => [
      for (final row in rows.cast<Map<String, dynamic>>())
        if (FaqCategory.values.where((c) => c.wire == row['category']).firstOrNull case final category?)
          FaqItem(
            id: row['id'] as String,
            category: category,
            question: row['question'] as String,
            answer: row['answer'] as String,
            sortOrder: row['sort_order'] as int,
          ),
    ];
