import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/http_kakao_id_repository.dart';
import 'package:campus_mate/profile/model/kakao_id_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final kakaoIdRepositoryProvider = Provider<KakaoIdRepository>((ref) {
  return HttpKakaoIdRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
