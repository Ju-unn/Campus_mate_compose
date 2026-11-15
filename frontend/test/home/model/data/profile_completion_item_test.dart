import 'package:campus_mate/home/model/data/profile_completion_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 값(`GET /home/summary` profile_completion_missing)을 항목으로 읽는다', () {
    expect(
      ['photos', 'mbti', 'preferred_height', 'interest_tags'].map(ProfileCompletionItem.tryParse),
      ProfileCompletionItem.values,
    );
  });

  test('모르는 값 · 글자가 아닌 값은 null 이다', () {
    for (final value in <Object?>['bio', '', null, 3]) {
      expect(ProfileCompletionItem.tryParse(value), isNull, reason: '$value');
    }
  });
}
