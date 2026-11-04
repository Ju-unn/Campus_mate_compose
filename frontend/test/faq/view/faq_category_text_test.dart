import 'package:campus_mate/faq/model/data/faq_item.dart';
import 'package:campus_mate/faq/view/faq_category_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('묶음 이름은 DESIGN §8.13 · pen 탭 순서다', () {
    final l10n = AppLocalizationsKo();

    expect(FaqCategory.values.map((category) => category.label(l10n)), ['카드·매칭', '하트·결제', '사진·프로필', '지인 리뷰', '안전·신고', '계정']);
  });
}
