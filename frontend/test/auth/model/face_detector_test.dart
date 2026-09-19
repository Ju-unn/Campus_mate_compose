import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'fake_face_detector.dart';

void main() {
  test('기본값은 얼굴을 찾은 것으로 처리한다', () async {
    final detector = FakeFaceDetector();

    final hasFace = await detector.hasFace(File('dummy.jpg'));

    expect(hasFace, isTrue);
  });

  test('nextResult를 지정하면 그 값을 돌려준다', () async {
    final detector = FakeFaceDetector()..nextResult = false;

    final hasFace = await detector.hasFace(File('dummy.jpg'));

    expect(hasFace, isFalse);
  });
}
