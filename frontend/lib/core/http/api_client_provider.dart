import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 저장소 provider 15개가 각자 `http.Client()` 를 새로 만들던 것을 하나로 합친다 —
/// 연결도 재사용되고, `--dart-define` 으로 온 base URL 을 적는 자리도 한 곳이다.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
