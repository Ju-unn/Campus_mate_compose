import 'dart:js_interop';

@JS('open')
external JSAny? _open(String url, String target, String features);

/// `window.open(url, '_blank', 'noopener')` — 열린 탭이 이 관리자 창을 만지지 못하게 noopener.
void openLink(String url) => _open(url, '_blank', 'noopener');
