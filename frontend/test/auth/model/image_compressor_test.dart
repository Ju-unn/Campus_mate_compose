import 'dart:io';

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
}
