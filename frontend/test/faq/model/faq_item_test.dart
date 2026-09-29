import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object> row(String category, {String id = 'a'}) =>
      {'id': id, 'category': category, 'question': '질문', 'answer': '답', 'sort_order': 10};

  test('묶음 값을 enum 으로 읽는다', () {
    final items = parseFaqRows([row('heart_payment')]);
    expect(items.single.category, FaqCategory.heartPayment);
    expect(items.single.sortOrder, 10);
  });

  test('모르는 묶음 행은 버린다 — 나머지는 그대로', () {
    final items = parseFaqRows([row('new_kind', id: 'x'), row('safety', id: 'y')]);
    expect(items.map((i) => i.id), ['y']);
  });

  test('toJson 을 다시 읽으면 같은 값이다(캐시 왕복)', () {
    final item = parseFaqRows([row('account')]).single;
    final back = parseFaqRows([item.toJson()]).single;
    expect([back.id, back.category, back.question, back.answer, back.sortOrder],
        [item.id, item.category, item.question, item.answer, item.sortOrder]);
  });

  test('묶음 이름은 DESIGN §8.13 · pen 탭 순서다', () {
    expect(FaqCategory.values.map((c) => c.label),
        ['카드·매칭', '하트·결제', '사진·프로필', '지인 리뷰', '안전·신고', '계정']);
  });
}
