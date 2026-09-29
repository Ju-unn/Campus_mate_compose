import 'dart:io';

import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('남길 사진은 행 id 가 같으면 같은 칸이다', () {
    expect(const KeptPhoto('p-a'), const KeptPhoto('p-a'));
    expect(const KeptPhoto('p-a').hashCode, const KeptPhoto('p-a').hashCode);
    expect(const KeptPhoto('p-a'), isNot(const KeptPhoto('p-b')));
  });

  test('새 사진은 파일 경로가 같으면 같은 칸이다', () {
    expect(NewPhoto(File('a.jpg')), NewPhoto(File('a.jpg')));
    expect(NewPhoto(File('a.jpg')).hashCode, NewPhoto(File('a.jpg')).hashCode);
    expect(NewPhoto(File('a.jpg')), isNot(NewPhoto(File('b.jpg'))));
  });

  test('남길 사진과 새 사진은 서로 다르다', () {
    expect(const KeptPhoto('a.jpg'), isNot(NewPhoto(File('a.jpg'))));
  });
}
