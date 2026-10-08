import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [DraftStore] 를 `shared_preferences` 로 구현한다.
///
/// - 키: `onboarding_draft/{계정 id}/{화면 키}`. 계정 id 는 로그인 상태(Supabase 세션의 사용자 id)에서 그때그때 읽는다.
/// - 값: `{"version": 1, "data": {...}, "files": [...]}` JSON 문자열. 버전이나 모양이 안 맞으면 조용히 버린다.
/// - 쓰기: 마지막 변경 뒤 [defaultDebounce] 가 지나면 한 번 쓴다. 그 사이 읽으면 기다리는 값을 돌려준다.
/// - 계정이 바뀌면(다른 계정 id 로 읽거나 쓰면) 옛 계정 값과 딸린 파일부터 지운다.
///
/// 읽기는 동기다 — 뷰모델이 처음 상태를 만들 때(build) 바로 채워야 입력칸의 처음 값으로 들어간다.
/// 그래서 앱을 켤 때 [SharedPreferences.getInstance] 로 디스크를 한 번 읽어 둔 인스턴스를 받는다.
class SharedPreferencesDraftStore implements DraftStore {
  SharedPreferencesDraftStore(
    this._preferences, {
    required this._accountId,
    required String fileDirectory,
    this._debounce = defaultDebounce,
  }) : _fileDirectory = _withoutTrailingSeparator(Directory(fileDirectory).absolute.path);

  static const String keyPrefix = 'onboarding_draft';

  /// 저장 모양의 버전. 화면이 남기는 값의 모양을 바꾸면 올린다 — 옛 값은 읽을 때 버려진다.
  static const int version = 1;

  /// 입력이 멈춘 뒤 이만큼 기다렸다가 쓴다.
  static const Duration defaultDebounce = Duration(milliseconds: 500);

  final SharedPreferences _preferences;
  final String? Function() _accountId;
  final Duration _debounce;

  /// 지워도 되는 파일이 사는 곳(앱 임시 폴더). 이 밖의 경로는 저장돼 있어도 지우지 않는다.
  final String _fileDirectory;

  /// 아직 디스크에 안 쓴 값. 키마다 마지막 값 하나만 기다린다.
  final Map<String, _PendingWrite> _pending = {};

  @override
  T? read<T>(DraftScreen screen, T Function(Map<String, Object?> data) decode) {
    final key = _keyOf(screen);
    final raw = key == null ? null : _rawOf(key);
    if (raw == null) {
      return null;
    }
    try {
      return decode(_dataOf(raw));
    } on Object {
      unawaited(_discard(key!)); // 버전 · 모양이 안 맞는 값 — 다음에 또 걸리지 않게 지운다.
      return null;
    }
  }

  @override
  void write(DraftScreen screen, Map<String, Object?> data, {List<String> files = const []}) {
    final key = _keyOf(screen);
    if (key == null) {
      return; // 로그인 전에는 주인이 없다.
    }
    _pending.remove(key)?.cancel();
    final raw = jsonEncode({'version': version, 'data': data, 'files': files});
    _pending[key] = _PendingWrite(raw, Timer(_debounce, () => _flush(key)));
  }

  @override
  Future<void> clear(DraftScreen screen) async {
    final key = _keyOf(screen);
    if (key == null) {
      return;
    }
    await _discard(key);
  }

  @override
  Future<void> clearAll() async {
    final keys = {..._pending.keys, ..._preferences.getKeys().where(_isDraftKey)};
    await Future.wait(keys.map(_discard));
  }

  /// 지금 계정의 키. 로그인 전이면 null. 계정이 바뀌었으면 옛 계정 값부터 지운다.
  String? _keyOf(DraftScreen screen) {
    final account = _accountId();
    if (account == null) {
      return null;
    }
    _forgetOtherAccounts(account);
    return '$keyPrefix/$account/${screen.key}';
  }

  void _forgetOtherAccounts(String account) {
    final others = {..._pending.keys, ..._preferences.getKeys()}
        .where((key) => _isDraftKey(key) && !key.startsWith('$keyPrefix/$account/'));
    for (final key in others.toList()) {
      unawaited(_discard(key));
    }
  }

  bool _isDraftKey(String key) => key.startsWith('$keyPrefix/');

  String? _rawOf(String key) => _pending[key]?.raw ?? _preferences.getString(key);

  void _flush(String key) {
    final pending = _pending.remove(key);
    if (pending == null) {
      return;
    }
    unawaited(_preferences.setString(key, pending.raw));
  }

  /// 기다리는 쓰기를 취소하고, 디스크 값과 딸린 파일을 지운다.
  Future<void> _discard(String key) async {
    final pending = _pending.remove(key)?..cancel();
    _deleteFiles({..._filesOf(pending?.raw), ..._filesOf(_preferences.getString(key))});
    await _preferences.remove(key);
  }

  /// 버전이 같고 `data` 가 맵인 봉투만 받는다. 아니면 던진다 — [read] 가 받아 버린다.
  Map<String, Object?> _dataOf(String raw) {
    final envelope = jsonDecode(raw) as Map<String, Object?>;
    if (envelope['version'] != version) {
      throw const FormatException('다른 버전의 임시 저장 값');
    }
    return envelope['data'] as Map<String, Object?>;
  }

  /// 봉투에 적힌 딸린 파일. 읽을 수 없는 봉투면 지울 것도 없다(남의 경로를 믿지 않는다).
  Iterable<String> _filesOf(String? raw) {
    try {
      final envelope = jsonDecode(raw ?? '{}') as Map<String, Object?>;
      return envelope['version'] == version ? (envelope['files'] as List? ?? const []).whereType<String>() : const [];
    } on Object {
      return const [];
    }
  }

  /// [path] 가 앱 임시 폴더 **안**에 있는가. 저장된 경로를 그대로 믿지 않는다 — `..` 로 빠져나가는 경로와,
  /// 이름 앞부분만 같은 이웃 폴더(`/tmp_other`)는 밖으로 본다.
  bool _isInsideFileDirectory(String path) {
    final separator = Platform.pathSeparator;
    final absolute = File(path).absolute.path;
    if (absolute.split(separator).contains('..')) {
      return false;
    }
    return absolute.startsWith('$_fileDirectory$separator');
  }

  /// 시스템이 임시 폴더를 이미 비웠을 수 있다 — 없는 파일은 건너뛴다. 앱 임시 폴더 밖의 경로는 지우지 않는다.
  void _deleteFiles(Iterable<String> paths) {
    for (final path in paths.where(_isInsideFileDirectory)) {
      final file = File(path);
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } on FileSystemException {
        // 지우지 못한 임시 파일은 시스템이 언젠가 비운다 — 로그아웃 · 다음 단계를 막을 일이 아니다.
      }
    }
  }
}

/// 경로 끝의 구분자를 뗀다 — `/tmp/` 와 `/tmp` 를 같게 본다.
String _withoutTrailingSeparator(String path) {
  final separator = Platform.pathSeparator;
  return path.length > 1 && path.endsWith(separator) ? path.substring(0, path.length - 1) : path;
}

/// 디바운스 중인 쓰기 하나. 마지막 값과 그 값을 쓸 타이머.
class _PendingWrite {
  _PendingWrite(this.raw, this._timer);

  final String raw;
  final Timer _timer;

  void cancel() => _timer.cancel();
}
