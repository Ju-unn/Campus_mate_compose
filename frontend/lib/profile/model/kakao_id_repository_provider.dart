import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/http_kakao_id_repository.dart';
import 'package:campus_mate/profile/model/kakao_id_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kakaoIdRepositoryProvider = Provider<KakaoIdRepository>((ref) {
  return HttpKakaoIdRepository(ref.read(apiClientProvider));
});
