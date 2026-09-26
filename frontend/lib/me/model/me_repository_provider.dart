import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/me/model/http_me_repository.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 화면 15 가 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final meRepositoryProvider = Provider<MeRepository>((ref) {
  return HttpMeRepository(ref.read(apiClientProvider));
});
