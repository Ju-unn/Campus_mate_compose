import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/safety/model/http_safety_repository.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 신고 시트 · 14e 차단 · 16f 차단 목록이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return HttpSafetyRepository(ref.read(apiClientProvider));
});
