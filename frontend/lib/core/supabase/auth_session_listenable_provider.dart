import 'package:campus_mate/core/supabase/auth_session_listenable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 앱 전체가 같은 세션 리스너를 본다 — main.dart 는 라우터 `refreshListenable` 에 걸고,
/// 시작 화면은 로그아웃이 확인된 뒤에만 소셜 로그인 버튼을 그린다.
///
/// 세션 복원은 `Supabase.initialize`(main 의 `runApp` 전)에서 끝난다(supabase_flutter 2.17 이 그 안에서
/// `initialSession` 을 알린다). 그래서 이 리스너가 처음 만들어질 때 이미 로그인 여부를 안다.
final authSessionListenableProvider = Provider<AuthSessionListenable>((ref) {
  final listenable = AuthSessionListenable(Supabase.instance.client);
  ref.onDispose(listenable.dispose);
  return listenable;
});
