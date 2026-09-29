import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/consent_repository.dart';

/// 테스트 전용 [ConsentRepository]. 기본은 성공이고, [gate] 를 걸면 끝나기 전 상태를 볼 수 있다.
class FakeConsentRepository implements ConsentRepository {
  Result<void> nextResult = const Success(null);
  Completer<void>? gate;
  final List<Set<ConsentItem>> submitted = [];

  @override
  Future<Result<void>> submit({required Set<ConsentItem> agreed}) async {
    submitted.add(agreed);
    await gate?.future;
    return nextResult;
  }
}
