import 'package:campus_mate/auth/model/auth_repository.dart';
import 'package:campus_mate/auth/model/supabase_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(Supabase.instance.client.auth);
});
