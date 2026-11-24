// 그림 파일 하나를 고른다(공지 그림). 웹에서만 실제로 동작하고, 시험(VM)에서는 고른 것이 없다(null).
// 새 부품 없이 SDK 의 dart:js_interop 만 쓴다(page_reload 와 같은 조건부 import).
export 'pick_image_stub.dart' if (dart.library.js_interop) 'pick_image_web.dart';
