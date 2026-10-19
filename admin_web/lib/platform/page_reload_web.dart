import 'dart:js_interop';

@JS('location')
external _Location get _location;

extension type _Location._(JSObject _) implements JSObject {
  external void reload();
}

/// `window.location.reload()` — 새로 배포된 빌드(dart-define 값이 채워진)를 받아 온다.
void reloadPage() => _location.reload();
