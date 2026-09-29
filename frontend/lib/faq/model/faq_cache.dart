import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 마지막으로 받은 FAQ(DESIGN §8.13 "마지막 응답을 로컬에 캐시").
abstract interface class FaqCache {
  /// 없거나 읽을 수 없으면 빈 목록.
  Future<List<FaqItem>> load();

  Future<void> save(List<FaqItem> items);
}

/// 개인정보가 아니라 로그아웃해도 지우지 않는다. 모양은 [parseFaqRows] 가 읽는 표 행 그대로다.
class FileFaqCache implements FaqCache {
  FileFaqCache(this._directory);

  final Future<Directory> Function() _directory;
  static const _fileName = 'faq_cache.json';

  @override
  Future<List<FaqItem>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      return parseFaqRows(jsonDecode(await file.readAsString()) as List<dynamic>);
    } on Object {
      // 깨진 파일은 없는 것과 같다 — 다음에 받으면 덮어쓴다.
      return const [];
    }
  }

  @override
  Future<void> save(List<FaqItem> items) async {
    final file = await _file();
    await file.writeAsString(jsonEncode([for (final item in items) item.toJson()]));
  }

  Future<File> _file() async => File('${(await _directory()).path}/$_fileName');
}

final faqCacheProvider = Provider<FaqCache>((ref) => FileFaqCache(getApplicationSupportDirectory));
