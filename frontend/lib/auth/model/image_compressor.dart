import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// 업로드 전 사진을 압축하고 JPEG 로 다시 인코딩한다(설계 §7.4).
abstract interface class ImageCompressor {
  Future<File> compressToJpeg(File source);
}

/// `flutter_image_compress` 로 [ImageCompressor] 를 구현한다.
class FlutterImageCompressor implements ImageCompressor {
  @override
  Future<File> compressToJpeg(File source) async {
    final targetDir = await getTemporaryDirectory();
    final targetPath = '${targetDir.path}/student-id-${DateTime.now().microsecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      targetPath,
      quality: 85,
      format: CompressFormat.jpeg,
    );
    return result == null ? source : File(result.path);
  }
}
