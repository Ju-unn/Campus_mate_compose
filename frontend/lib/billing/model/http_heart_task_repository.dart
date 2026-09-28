import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [HeartTaskRepository] 를 FastAPI 호출로 구현한다. 상태코드 분류는 `sendAuthorizedRequest` 가 한다.
class HttpHeartTaskRepository implements HeartTaskRepository {
  const HttpHeartTaskRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<List<HeartTask>>> fetchTasks() => _api.send(
        'GET',
        '/heart-tasks',
        (body) => ((body as Map<String, dynamic>)['tasks'] as List<dynamic>)
            .map((item) => HeartTask.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  /// 인증샷은 multipart 라 JSON 지름길([ApiClient.send])을 쓰지 못한다.
  @override
  Future<Result<HeartTask>> submit(HeartTaskKind kind, File photo) async {
    final result = await _api.sendMultipart('/heart-tasks/${kind.code}/submissions', const {}, photo.path);
    return result.when(
      onSuccess: (response) {
        // ApiClient.send 와 같은 이유 — 약속과 다른 본문의 캐스트 오류가 Result 밖으로 튀면 화면이 멈춘다.
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return Success(HeartTask.fromJson(body['task'] as Map<String, dynamic>));
        } catch (_) {
          return const FailureResult<HeartTask>(UnknownFailure());
        }
      },
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
