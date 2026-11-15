import 'dart:io';

import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/common/result.dart';

/// 무료로 하트 모으기(18a · 18b)가 쓰는 서버 호출 전부.
abstract interface class HeartTaskRepository {
  /// 서버가 준 순서 그대로(지금 서버는 단톡방 · 투표 두 줄). 앱이 모르는 항목 줄은 빼고 돌려준다.
  Future<Result<List<HeartTask>>> fetchTasks();

  /// [photos] 는 압축한 JPEG 1~3장(고른 순서). 한 요청으로 보낸다. 성공하면 그 항목의 새 줄(보통 검수 중)을 돌려준다.
  Future<Result<HeartTask>> submit(HeartTaskKind kind, List<File> photos);
}
