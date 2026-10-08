import 'dart:convert';

import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

/// [DraftStore] 를 흉내 낸다. 기다림(디바운스) 없이 곧바로 담고, 담은 값은 JSON 으로 한 번 돌려 실제 저장소처럼
/// 숫자 · 목록 모양이 바뀌게 한다. 계정별로 따로 담는다 — [accountId] 를 바꾸면 다른 계정으로 로그인한 것과 같다.
class FakeDraftStore implements DraftStore {
  FakeDraftStore({this.accountId = 'account-a'});

  /// 지금 로그인한 계정. null 이면 로그인 전이다.
  String? accountId;

  /// `계정/화면` → JSON 문자열. 시험이 "무엇이 저장소에 들어갔는지" 를 문자열로 직접 본다.
  final Map<String, String> saved = {};

  /// 값과 함께 지울 파일 경로(사진). 지울 때 [deletedFiles] 로 옮긴다.
  final Map<String, List<String>> files = {};
  final List<String> deletedFiles = [];
  final List<DraftScreen> cleared = [];
  int clearAllCalls = 0;

  String _key(String account, DraftScreen screen) => '$account/${screen.key}';

  /// 저장소에 들어간 모든 글자. 전화번호 · 카카오톡 아이디가 섞이지 않았는지 볼 때 쓴다.
  String get dump => saved.values.join('\n');

  @override
  T? read<T>(DraftScreen screen, T Function(Map<String, Object?> data) decode) {
    final account = accountId;
    final raw = account == null ? null : saved[_key(account, screen)];
    if (raw == null) {
      return null;
    }
    try {
      return decode(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      saved.remove(_key(account!, screen));
      return null;
    }
  }

  @override
  void write(DraftScreen screen, Map<String, Object?> data, {List<String> files = const []}) {
    final account = accountId;
    if (account == null) {
      return;
    }
    saved[_key(account, screen)] = jsonEncode(data);
    this.files[_key(account, screen)] = [...files];
  }

  @override
  Future<void> clear(DraftScreen screen) async {
    cleared.add(screen);
    final account = accountId;
    if (account == null) {
      return;
    }
    saved.remove(_key(account, screen));
    deletedFiles.addAll(files.remove(_key(account, screen)) ?? const []);
  }

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
    saved.clear();
    deletedFiles.addAll(files.values.expand((paths) => paths));
    files.clear();
  }
}
