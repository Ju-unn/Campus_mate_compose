import 'dart:async';
import 'dart:io';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 기기 연락처 · 권한 가짜. 권한 흐름은 [granted] · [grantOnRequest] 로 정한다.
class FakeDeviceContactSource implements DeviceContactSource {
  FakeDeviceContactSource({this.granted = false, this.grantOnRequest = true, this.contacts = const []});

  bool granted;

  /// 권한 창에서 허용할지. false 면 "다시 묻지 않음"처럼 곧바로 거부가 온다.
  bool grantOnRequest;
  List<DeviceContact> contacts;

  /// 채우면 fetchAll 이 이것을 던진다 — 읽는 도중 권한이 꺼진 경우.
  Exception? fetchError;

  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    requestCount += 1;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<void> openSettings() async => openSettingsCount += 1;

  @override
  Future<List<DeviceContact>> fetchAll() async {
    if (fetchError case final error?) throw error;
    return contacts;
  }
}

/// 서버 가짜. [addResult] 를 비워 두면 번호마다 `b<순번>` id 를 돌려준다.
class FakeContactBlockRepository implements ContactBlockRepository {
  Result<List<String?>>? addResult;
  Result<List<ContactBlock>> blocks = const Success([]);
  Result<void> removeResult = const Success(null);

  final List<List<String>> added = [];
  final List<String> removed = [];
  int fetchCount = 0;
  Completer<void>? holdAdd;

  @override
  Future<Result<List<String?>>> add(List<String> numbers) async {
    added.add(numbers);
    await holdAdd?.future;
    return addResult ?? Success([for (var i = 0; i < numbers.length; i++) 'b${i + 1}']);
  }

  @override
  Future<Result<List<ContactBlock>>> fetch() async {
    fetchCount += 1;
    return blocks;
  }

  @override
  Future<Result<void>> remove(String blockId) async {
    removed.add(blockId);
    return removeResult;
  }
}

/// 이름표 가짜. 파일 대신 메모리에 둔다.
class FakeContactNameStore implements ContactNameStore {
  FakeContactNameStore([Map<String, ContactLabel>? labels]) : labels = {...?labels};

  final Map<String, ContactLabel> labels;

  /// 참이면 saveAll 이 파일 쓰기 실패처럼 던진다.
  bool failSave = false;

  /// 참이면 remove 가 파일 쓰기 실패처럼 던진다.
  bool failRemove = false;

  @override
  Future<Map<String, ContactLabel>> load() async => {...labels};

  @override
  Future<void> saveAll(Map<String, ContactLabel> labelsByBlockId) async {
    if (failSave) throw const FileSystemException('disk full');
    labels.addAll(labelsByBlockId);
  }

  @override
  Future<void> remove(String blockId) async {
    if (failRemove) throw const FileSystemException('disk full');
    labels.remove(blockId);
  }
}

ContactBlock contactBlockFixture(String id) => ContactBlock(id: id, createdAt: DateTime(2026, 9, 27, 14));

const momContact = DeviceContact(id: 'c-mom', name: '엄마', numbers: ['010-1111-2841', '02-123-4567']);
const siblingContact = DeviceContact(id: 'c-sib', name: '동생', numbers: ['010-2222-7710']);

/// ContactRow 는 번호를 하이픈 조각으로 나눠 그리고 읽어 주기만 한 줄로 묶는다 — 그 한 줄로 찾는다.
Finder maskedNumber(String number) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == number);
