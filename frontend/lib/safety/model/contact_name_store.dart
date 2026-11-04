import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/safety/model/contact_label.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 차단 id → 이름표. 서버는 id 와 등록일만 안다.
abstract interface class ContactNameStore {
  Future<Map<String, ContactLabel>> load();

  /// 이미 있는 이름표에 더한다(같은 id 는 덮어쓴다).
  Future<void> saveAll(Map<String, ContactLabel> labelsByBlockId);

  Future<void> remove(String blockId);

  /// 이름표를 전부 지운다 — 로그아웃 · 탈퇴 때. 다음에 이 폰으로 로그인하는 사람이 앞사람이 차단한 지인 이름을 보지 않는다.
  Future<void> clear();
}

/// 16b 가 보여줄 이름을 **기기에만** 둔다(ERD §5). 서버는 id 와 등록일만 안다.
/// 앱을 다시 깔면 파일이 사라져 "이전에 차단한 연락처"로 보인다 — 의도된 모습이다.
///
/// 파일 모양: `{"<blockId>": {"name": "…", "number": "010-****-2841"}}` — 번호 원문은 저장하지 않는다.
class FileContactNameStore implements ContactNameStore {
  FileContactNameStore(this._directory);

  final Future<Directory> Function() _directory;
  static const _fileName = 'contact_block_names.json';

  @override
  Future<Map<String, ContactLabel>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      return _decode(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // 깨진 파일 때문에 16b 가 안 열리면 해제도 못 한다 — 이름 없이 연다.
      return {};
    }
  }

  @override
  Future<void> saveAll(Map<String, ContactLabel> labelsByBlockId) async {
    final labels = await load()
      ..addAll(labelsByBlockId);
    await _write(labels);
  }

  @override
  Future<void> remove(String blockId) async {
    final labels = await load()
      ..remove(blockId);
    await _write(labels);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async => File('${(await _directory()).path}/$_fileName');

  Future<void> _write(Map<String, ContactLabel> labels) async {
    final json = {
      for (final MapEntry(:key, :value) in labels.entries)
        key: {'name': value.name, 'number': value.maskedNumber},
    };
    await (await _file()).writeAsString(jsonEncode(json));
  }

  /// 칸이 모자란 항목은 건너뛴다.
  static Map<String, ContactLabel> _decode(Map<String, dynamic> json) => {
        for (final MapEntry(:key, :value) in json.entries)
          if (value case {'name': final String name, 'number': final String number})
            key: ContactLabel(name: name, maskedNumber: number),
      };
}

final contactNameStoreProvider = Provider<ContactNameStore>(
  (ref) => FileContactNameStore(getApplicationSupportDirectory),
);
