import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:campus_mate_admin/notices/notice_item.dart' show NoticeImageTooLarge, maxNoticeImageBytes;

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external _Input createElement(String tag);
}

extension type _Input._(JSObject _) implements JSObject {
  external set type(String value);
  external set accept(String value);
  external _FileList? get files;
  external void click();
  external void addEventListener(String type, JSFunction listener);
}

extension type _FileList._(JSObject _) implements JSObject {
  external _File? item(int index);
}

extension type _File._(JSObject _) implements JSObject {
  external String get name;
  external int get size;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// 숨은 `<input type=file>` 로 jpeg · png · webp 하나를 고른다. 취소하면 null(cancel 이벤트).
/// [maxNoticeImageBytes] 를 넘으면 읽기 전에 [NoticeImageTooLarge] 를 던진다(큰 파일을 통째로 메모리에 올리지 않게).
/// 형식 · 크기는 서버가 다시 본다 — accept 는 고르는 창의 거르기일 뿐이다.
Future<({Uint8List bytes, String name})?> pickImage() async {
  final input = _document.createElement('input')
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,image/webp';
  final chosen = Completer<_File?>();
  void finish(JSAny? _) {
    if (!chosen.isCompleted) chosen.complete(input.files?.item(0));
  }

  // shortcut: cancel 이벤트 미지원 브라우저(Safari 16.4 미만 등)는 취소해도 Future 가 남음, 화면은 잠기지 않음 — 문제 되면 window focus 로 끝내기
  input
    ..addEventListener('change', finish.toJS)
    ..addEventListener('cancel', finish.toJS)
    ..click();
  final file = await chosen.future;
  if (file == null) return null;
  if (file.size > maxNoticeImageBytes) throw const NoticeImageTooLarge();
  final buffer = await file.arrayBuffer().toDart;
  return (bytes: buffer.toDart.asUint8List(), name: file.name);
}
