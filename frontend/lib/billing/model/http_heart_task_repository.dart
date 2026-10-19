import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:http/http.dart' as http;

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

  /// 인증샷은 multipart 라 JSON 지름길([ApiClient.send])을 쓰지 못하고, `sendMultipart` 는 파일 하나(`photo`)뿐이라
  /// `sendRequest` 로 직접 만든다 — 사진은 고른 순서대로 담는다. 한 장이면 옛 서버도 읽는 `photo` 칸으로,
  /// 여러 장이면 `photos` 칸으로 보낸다(새 서버는 둘 다 받는다. 옛 서버는 한 장까지라 늘 한 장이다).
  @override
  Future<Result<HeartTask>> submit(HeartTaskKind kind, List<File> photos) async {
    final result = await _api.sendRequest((accessToken) async {
      final request = http.MultipartRequest('POST', _api.uri('/heart-tasks/${kind.code}/submissions'))
        ..headers['Authorization'] = 'Bearer $accessToken';
      final field = photos.length == 1 ? 'photo' : 'photos';
      for (final photo in photos) {
        request.files.add(await http.MultipartFile.fromPath(field, photo.path));
      }
      return request;
    });
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
