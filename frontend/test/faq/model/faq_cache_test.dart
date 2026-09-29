import 'dart:io';

import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_faq.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('faq_cache'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('저장한 목록을 그대로 읽는다', () async {
    final cache = FileFaqCache(() async => dir);
    await cache.save(faqFixture);
    final loaded = await cache.load();
    expect(loaded.map((i) => i.id), faqFixture.map((i) => i.id));
    expect(loaded.last.question, faqFixture.last.question);
  });

  test('파일이 없으면 빈 목록', () async {
    expect(await FileFaqCache(() async => dir).load(), isEmpty);
  });

  test('깨진 파일은 빈 목록', () async {
    File('${dir.path}/faq_cache.json').writeAsStringSync('{not json');
    expect(await FileFaqCache(() async => dir).load(), isEmpty);
  });
}
