import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';

class FakeBioRepository implements BioRepository {
  Result<String> nextDraftResult = const Success('안녕하세요! 활발한 성격이에요.');
  Result<void> nextSubmitResult = const Success(null);
  int draftCount = 0;
  String? submittedBio;

  /// 채워 두면 초안 만들기가 이 Completer 가 끝날 때까지 기다린다(06-2b "만드는 중" 확인용).
  Completer<void>? holdDraft;

  @override
  Future<Result<String>> generateDraft() async {
    draftCount++;
    await holdDraft?.future;
    return nextDraftResult;
  }

  @override
  Future<Result<void>> submit(String bio) async {
    submittedBio = bio;
    return nextSubmitResult;
  }
}
