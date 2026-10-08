import 'dart:io';

import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/open_draft_store.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<String> logs;

  setUp(() {
    logs = [];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = original);
  });

  test('디스크를 열면 진짜 저장소를 준다', () async {
    SharedPreferences.setMockInitialValues({});

    final drafts = await openDraftStore(
      accountId: () => 'account-a',
      temporaryDirectory: () async => Directory.systemTemp,
    );

    expect(drafts, isA<SharedPreferencesDraftStore>());
    expect(logs, isEmpty);
  });

  test('SharedPreferences 를 열지 못하면 앱은 그대로 뜨고 임시 저장 없이(NoDraftStore) 간다', () async {
    final drafts = await openDraftStore(
      accountId: () => 'account-a',
      preferences: () async => throw StateError('disk broke: 010-1234-5678'),
      temporaryDirectory: () async => Directory.systemTemp,
    );

    expect(drafts, isA<NoDraftStore>());
    expect(logs, hasLength(1), reason: '못 연 사실은 남긴다');
    expect(logs.single, isNot(contains('010-1234-5678')), reason: '로그에 값(예외 문구)을 남기지 않는다');
  });

  test('앱 임시 폴더를 찾지 못해도 임시 저장 없이 간다', () async {
    SharedPreferences.setMockInitialValues({});

    final drafts = await openDraftStore(
      accountId: () => 'account-a',
      temporaryDirectory: () async => throw const FileSystemException('no temp dir', '/secret/path'),
    );

    expect(drafts, isA<NoDraftStore>());
    expect(logs.single, isNot(contains('/secret/path')));
  });
}
