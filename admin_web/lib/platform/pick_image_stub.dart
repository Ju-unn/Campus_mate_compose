import 'dart:typed_data';

/// 브라우저가 아닌 곳(시험)에서는 고를 파일이 없다.
Future<({Uint8List bytes, String name})?> pickImage() async => null;
