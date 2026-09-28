import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 16b 한 줄에 보일 이름과 가린 번호(pen `GC2LV` — 이름 · 번호 두 줄).
class ContactLabel {
  const ContactLabel({required this.name, required this.maskedNumber});

  final String name;
  final String maskedNumber;
}

/// 차단 id → 이름표. 서버는 id 와 등록일만 안다.
abstract interface class ContactNameStore {
  Future<Map<String, ContactLabel>> load();

  /// 이미 있는 이름표에 더한다(같은 id 는 덮어쓴다).
  Future<void> saveAll(Map<String, ContactLabel> labelsByBlockId);

  Future<void> remove(String blockId);
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

/// 한국 국가번호. 연락처 앱은 `+82 10-…` 로도 적는다.
const String _koreaCountryCode = '82';

/// 가린 번호로 보이는 최소 자릿수 — 휴대전화(10~11자리). 이보다 짧은 번호(대표번호 등)는 원문 그대로 둔다.
const int _maskableMinDigits = 10;

/// pen 8d · 16b 처럼 `010-****-2841` 로 가린다. 숫자만 남기고, 앞 `82` 는 떼고 그 뒤 앞자리 0 을 지운 뒤
/// `0` 하나를 붙인다 — 서버 `to_e164` 와 같은 규칙이라 `+82 010-…` 도 `010-…` 이 된다.
String maskPhoneNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final local = digits.startsWith(_koreaCountryCode)
      ? '0${digits.substring(_koreaCountryCode.length).replaceFirst(RegExp('^0+'), '')}'
      : digits;
  if (local.length < _maskableMinDigits) return raw;
  return '${local.substring(0, 3)}-****-${local.substring(local.length - 4)}';
}
