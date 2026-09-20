import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/appearance_type_repository.dart';
import 'package:campus_mate/profile/model/http_appearance_type_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final appearanceTypeRepositoryProvider = Provider<AppearanceTypeRepository>((ref) {
  return HttpAppearanceTypeRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
