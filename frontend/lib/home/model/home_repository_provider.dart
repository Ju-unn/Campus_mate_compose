import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/home/model/home_repository.dart';
import 'package:campus_mate/home/model/http_home_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 09b 메인이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HttpHomeRepository(ref.read(apiClientProvider));
});
