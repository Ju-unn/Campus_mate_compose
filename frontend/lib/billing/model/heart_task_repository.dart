import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/common/result.dart';

/// 무료로 하트 모으기(18a · 18b)가 쓰는 서버 호출 전부.
abstract interface class HeartTaskRepository {
  /// 늘 세 줄 — 에브리타임 · 단톡방 · 투표 순.
  Future<Result<List<HeartTask>>> fetchTasks();

  /// [photos] 는 압축한 JPEG 1~3장(고른 순서). 한 요청으로 보낸다. 성공하면 그 항목의 새 줄(보통 검수 중)을 돌려준다.
  Future<Result<HeartTask>> submit(HeartTaskKind kind, List<File> photos);
}
