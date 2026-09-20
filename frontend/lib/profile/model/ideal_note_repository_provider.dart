import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/profile/model/http_ideal_note_repository.dart';
import 'package:campus_mate/profile/model/ideal_note_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final idealNoteRepositoryProvider = Provider<IdealNoteRepository>((ref) {
  return HttpIdealNoteRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
