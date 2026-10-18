// 브라우저 페이지를 다시 연다(설정 누락 화면). 웹에서만 실제로 동작하고, 시험(VM)에서는 아무것도 하지 않는다.
// 새 부품 없이 SDK 의 dart:js_interop 만 쓴다.
export 'page_reload_stub.dart' if (dart.library.js_interop) 'page_reload_web.dart';
