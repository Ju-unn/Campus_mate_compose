// 바깥 주소를 새 탭으로 연다(Crashlytics 링크). 웹에서만 실제로 동작하고, 시험(VM)에서는 아무것도 하지 않는다.
// 새 부품 없이 SDK 의 dart:js_interop 만 쓴다(page_reload 와 같은 조건부 import).
export 'open_link_stub.dart' if (dart.library.js_interop) 'open_link_web.dart';
