import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 값 free · career · love 를 앱 값으로 읽고 같은 글자로 돌려보낸다', () {
    for (final (wire, category) in [
      ('free', CommunityCategory.free),
      ('career', CommunityCategory.career),
      ('love', CommunityCategory.love),
    ]) {
      expect(CommunityCategory.fromWire(wire), category);
      expect(category.toWire(), wire);
    }
  });

  test('모르는 값 · 빈 값은 자유로 읽는다 — 서버가 나중에 값을 더해도 피드 한 줄이 깨지지 않게', () {
    expect(CommunityCategory.fromWire('notice'), CommunityCategory.free);
    expect(CommunityCategory.fromWire(null), CommunityCategory.free);
  });
}
