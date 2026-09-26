import 'package:campus_mate/community/model/community_repository.dart';
import 'package:campus_mate/community/model/http_community_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 커뮤니티 화면들이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return HttpCommunityRepository(ref.read(apiClientProvider));
});
