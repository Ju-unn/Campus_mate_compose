import 'dart:js_interop';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

/// `window.localStorage` — 막힌 창에서는 던진다(ConfirmStore 가 삼킨다).
String? readItem(String key) => _storage.getItem(key);

void writeItem(String key, String value) => _storage.setItem(key, value);
