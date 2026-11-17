// 서버 상태 [확인]으로 본 이상의 열쇠를 브라우저(localStorage)에 둔다 — DB 없이 PC · 휴대폰이 따로 센다(설계 2026-11-17).
// 새 부품 없이 SDK 의 dart:js_interop 만 쓴다(page_reload 와 같은 조건부 import). 시험(VM)에서는 아무것도 남지 않는다.
import 'dart:convert';

import 'package:campus_mate_admin/platform/confirm_store_stub.dart' if (dart.library.js_interop) 'package:campus_mate_admin/platform/confirm_store_web.dart' as storage;

/// 본 이상 열쇠("시각 UTC ISO|종류") 묶음. 값은 JSON 글자 배열 하나. 운영 정보가 아니라 로그아웃해도 지우지 않는다(대장 11-18).
class ConfirmStore {
  ConfirmStore({String? Function(String key)? readItem, void Function(String key, String value)? writeItem})
    : _readItem = readItem ?? storage.readItem,
      _writeItem = writeItem ?? storage.writeItem;

  static const String key = 'cm_admin_server_seen';

  final String? Function(String key) _readItem;
  final void Function(String key, String value) _writeItem;

  /// 시크릿 창 · 막힌 저장소 · 깨진 값이면 빈 묶음(아무것도 안 봄 — 이상을 모두 센다)
  Set<String> read() {
    try {
      final raw = _readItem(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toSet() : {};
      // 브라우저 저장소 오류는 JS 예외라 Exception 이 아닐 수 있다 — 무엇이든 삼킨다.
    } on Object {
      return {};
    }
  }

  /// 못 쓰면 버린다 — 이 창에서만 기억하고(상태), 다시 열면 이상을 다시 센다.
  void write(Set<String> keys) {
    try {
      _writeItem(key, jsonEncode(keys.toList()));
    } on Object {
      // 버린다
    }
  }
}
