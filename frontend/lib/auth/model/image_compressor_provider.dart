import 'package:campus_mate/auth/model/image_compressor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final imageCompressorProvider = Provider<ImageCompressor>((ref) {
  return FlutterImageCompressor();
});
