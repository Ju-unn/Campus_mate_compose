import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_mate/home/model/home_people.dart';
import 'package:flutter_test/flutter_test.dart';

/// 홈 레일 사람 칸(`GET /home/people`) — 서버가 흐리게 줄인 JPEG 를 base64 로 준다. 앱은 한 번 풀어 그대로 그린다.
void main() {
  final first = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
  final second = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1]);

  List<Uint8List> images(HomePeople people) => people.map((image) => image);

  test('서버 base64 를 한 번 풀어 받은 순서대로 그림 바이트로 둔다', () {
    final people = HomePeople.fromJson({
      'people': [base64Encode(first), base64Encode(second)],
    });

    expect(images(people), [first, second]);
    expect(people.isEmpty, isFalse);
  });

  test('잘못된 항목(base64 아님 · 빈 글 · 글이 아님)은 그 항목만 건너뛴다', () {
    final people = HomePeople.fromJson({
      'people': ['not base64!', '', 42, null, base64Encode(first)],
    });

    expect(images(people), [first]);
  });

  test('같은 그림이 두 번 오면 한 번만 둔다 — 한 벌에 같은 얼굴을 되풀이하지 않는다', () {
    final people = HomePeople.fromJson({
      'people': [base64Encode(first), base64Encode(second), base64Encode(first)],
    });

    expect(images(people), [first, second]);
  });

  test('빈 목록(서버 후보 10명 미만)이면 비어 있다 — 레일은 기본 그림 칸으로 대신한다', () {
    expect(HomePeople.fromJson({'people': <String>[]}).isEmpty, isTrue);
    expect(HomePeople.none.isEmpty, isTrue);
  });

  test('항목이 모두 잘못됐으면 비어 있다', () {
    expect(HomePeople.fromJson({'people': ['%%%', 7]}).isEmpty, isTrue);
  });
}
