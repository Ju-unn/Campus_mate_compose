import 'package:campus_mate/billing/model/heart_task_repository.dart';
import 'package:campus_mate/billing/model/http_heart_task_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 18a · 18b 가 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final heartTaskRepositoryProvider = Provider<HeartTaskRepository>((ref) {
  return HttpHeartTaskRepository(ref.read(apiClientProvider));
});
