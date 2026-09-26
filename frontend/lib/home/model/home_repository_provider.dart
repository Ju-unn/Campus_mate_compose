import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/mock_home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 09b 메인이 쓰는 저장소. 실제 API 가 생기면 이 줄만 `Http…` 구현으로 바꾼다.
/// 테스트는 이 provider 를 가짜로 덮어쓴다.
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return const MockHomeRepository();
});
