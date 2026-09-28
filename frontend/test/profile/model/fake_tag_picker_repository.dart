import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';

/// 태그 저장(04-5 · 04-6 · 06-2, 편집 모드도 같은 API)을 흉내 낸다. 받은 endpoint 와 태그를 남긴다.
class FakeTagPickerRepository implements TagPickerRepository {
  String? submittedEndpoint;
  List<String>? submittedTags;
  Result<void> nextResult = const Success(null);

  /// 채워 두면 저장이 이 Completer 가 끝날 때까지 기다린다("저장 중" 모양 확인용).
  Completer<void>? hold;

  @override
  Future<Result<void>> submit(String endpoint, List<String> tags) async {
    submittedEndpoint = endpoint;
    submittedTags = tags;
    await hold?.future;
    return nextResult;
  }
}
