import 'dart:async';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/common/result.dart';

/// pen 18a 세 줄(에브리타임 검수중 · 단톡방 완료 · 투표 미완료)과 같은 상태. [everytime] 으로 첫 줄 상태만 바꾼다.
/// 하트 수는 2026-10-16 사용자 확정 서버 값(에브리타임 40 · 단톡방 25 · 투표 5) — pen 글자(50 · 10)는 갱신 대기.
List<HeartTask> sampleHeartTasks({
  HeartTaskState everytime = HeartTaskState.reviewing,
  HeartTaskRejectReason? everytimeReason,
}) {
  final canSubmit = everytime == HeartTaskState.rejected || everytime == HeartTaskState.open;
  return [
    HeartTask(
      kind: HeartTaskKind.everytimePost,
      rewardHearts: 40,
      state: everytime,
      used: canSubmit ? 0 : 1,
      limit: 1,
      rejectReason: everytimeReason,
      canSubmit: canSubmit,
      maxPhotos: 3,
    ),
    const HeartTask(kind: HeartTaskKind.kakaoShare, rewardHearts: 25, state: HeartTaskState.done, used: 3, limit: 3, maxPhotos: 3),
    const HeartTask(kind: HeartTaskKind.pollVote, rewardHearts: 5, state: HeartTaskState.open, used: 0, limit: 3),
  ];
}

/// ViewModel · 화면 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeHeartTaskRepository implements HeartTaskRepository {
  Result<List<HeartTask>> tasks = Success(sampleHeartTasks());
  Result<HeartTask> submitResult = const Success(
    HeartTask(kind: HeartTaskKind.everytimePost, rewardHearts: 40, state: HeartTaskState.reviewing, used: 1, limit: 1),
  );

  int fetchCount = 0;
  final List<(HeartTaskKind, String)> submitted = [];

  /// 채워 두면 제출이 이것이 끝날 때까지 멈춘다 — 보내는 중에 한 번 더 누르는 상황용.
  Completer<void>? holdSubmit;

  @override
  Future<Result<List<HeartTask>>> fetchTasks() async {
    fetchCount++;
    return tasks;
  }

  @override
  Future<Result<HeartTask>> submit(HeartTaskKind kind, List<File> photos) async {
    // 기록은 쉼표로 이은 경로 문자열 — 레코드 비교가 리스트를 값으로 보지 않아서다.
    submitted.add((kind, photos.map((photo) => photo.path).join(',')));
    await holdSubmit?.future;
    return submitResult;
  }
}
