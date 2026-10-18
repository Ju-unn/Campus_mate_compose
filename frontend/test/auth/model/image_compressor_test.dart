import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_image_compressor.dart';

void main() {
  test('기본값은 입력 파일을 그대로 돌려준다', () async {
    final compressor = FakeImageCompressor();
    final source = File('source.jpg');

    final result = await compressor.compressToJpeg(source);

    expect(result, same(source));
  });

  test('nextResult를 지정하면 그 파일을 돌려준다', () async {
    final compressed = File('compressed.jpg');
    final compressor = FakeImageCompressor()..nextResult = compressed;

    final result = await compressor.compressToJpeg(File('source.jpg'));

    expect(result, same(compressed));
  });

  // 압축본(사진 사본)을 폰에 남기지 않는다(2026-10-18 보안 검사 낮음 6). 지우는 것은 이 압축기가 만든 이름뿐이다 —
  // 압축이 실패해 원본을 그대로 돌려준 경우 원본(갤러리 사본)과 다른 파일은 건드리지 않는다.
  group('FlutterImageCompressor 정리', () {
    late Directory dir;
    late FlutterImageCompressor compressor;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('image_compressor_test');
      compressor = FlutterImageCompressor(() async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File fileNamed(String name) => File('${dir.path}/$name')..writeAsStringSync('jpeg');

    test('discard 는 압축본을 지우고, 압축기가 만들지 않은 파일은 남긴다', () async {
      final compressed = fileNamed('student-id-1.jpg');
      final original = fileNamed('image_picker_abc.jpg');

      await compressor.discard(compressed);
      await compressor.discard(original);

      expect(compressed.existsSync(), isFalse);
      expect(original.existsSync(), isTrue);
      await expectLater(compressor.discard(compressed), completes, reason: '이미 지운 파일이어도 던지지 않는다');
    });

    test('discardAll 은 남은 압축본만 전부 지운다', () async {
      final first = fileNamed('student-id-1.jpg');
      final second = fileNamed('student-id-2.jpg');
      final other = fileNamed('draft-photo.jpg');

      await compressor.discardAll();

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });
}
