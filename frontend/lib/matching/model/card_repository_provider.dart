import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/model/http_card_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 조각 4 화면들이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return HttpCardRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
