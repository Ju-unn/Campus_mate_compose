import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';
import 'package:campus_mate/profile/model/http_bio_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final bioRepositoryProvider = Provider<BioRepository>((ref) {
  return HttpBioRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
