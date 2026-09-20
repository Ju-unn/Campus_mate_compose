import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/http_tag_picker_repository.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final tagPickerRepositoryProvider = Provider<TagPickerRepository>((ref) {
  return HttpTagPickerRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
