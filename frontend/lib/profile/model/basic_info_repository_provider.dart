import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';
import 'package:campus_mate/profile/model/http_basic_info_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final basicInfoRepositoryProvider = Provider<BasicInfoRepository>((ref) {
  return HttpBasicInfoRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
