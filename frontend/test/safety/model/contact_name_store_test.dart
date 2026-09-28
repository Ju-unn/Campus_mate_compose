import 'dart:io';

import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('contact_name_store_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  FileContactNameStore store() => FileContactNameStore(() async => dir);

  test('saveAll merges and load reads back', () async {
    await store().saveAll({'b1': const ContactLabel(name: '엄마', maskedNumber: '010-****-2841')});
    await store().saveAll({'b2': const ContactLabel(name: '동생', maskedNumber: '010-****-7710')});

    final labels = await store().load();

    expect(labels.keys, ['b1', 'b2']);
    expect(labels['b1']!.name, '엄마');
    expect(labels['b2']!.name, '동생');
    expect(labels['b2']!.maskedNumber, '010-****-7710');
  });

  test('the file keeps only the masked number, never the raw one', () async {
    await store().saveAll({'b1': const ContactLabel(name: '엄마', maskedNumber: '010-****-2841')});

    final text = File('${dir.path}/contact_block_names.json').readAsStringSync();

    expect(text, contains('010-****-2841'));
    expect(text, isNot(contains('1234')));
  });

  test('remove drops one id', () async {
    await store().saveAll({
      'b1': const ContactLabel(name: '엄마', maskedNumber: '010-****-2841'),
      'b2': const ContactLabel(name: '동생', maskedNumber: '010-****-7710'),
    });

    await store().remove('b1');

    final labels = await store().load();
    expect(labels.keys, ['b2']);
    expect(labels['b2']!.name, '동생');
  });

  test('load returns empty map when file is missing or broken', () async {
    expect(await store().load(), isEmpty);

    File('${dir.path}/contact_block_names.json').writeAsStringSync('{not json');
    expect(await store().load(), isEmpty);

    File('${dir.path}/contact_block_names.json').writeAsStringSync('[1, 2]');
    expect(await store().load(), isEmpty);
  });

  test('load skips entries missing a field', () async {
    File('${dir.path}/contact_block_names.json')
        .writeAsStringSync('{"b1": {"name": "엄마"}, "b2": {"name": "동생", "number": "010-****-7710"}}');

    final labels = await store().load();

    expect(labels.keys, ['b2']);
  });

  test('maskPhoneNumber', () {
    expect(maskPhoneNumber('010-1234-2841'), '010-****-2841');
    expect(maskPhoneNumber('+82 10-1234-2841'), '010-****-2841');
    // 서버 to_e164 처럼 82 뒤 앞자리 0 을 지우고 0 하나를 붙인다.
    expect(maskPhoneNumber('+82 010-1234-5678'), '010-****-5678');
    expect(maskPhoneNumber('01012342841'), '010-****-2841');
    expect(maskPhoneNumber('1588-0000'), '1588-0000');
  });
}
