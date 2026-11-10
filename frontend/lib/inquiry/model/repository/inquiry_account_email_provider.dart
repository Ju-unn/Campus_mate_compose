import 'package:campus_mate/inquiry/model/data/reply_email.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그인 계정이 이미 가진 메일(소셜 로그인 때 받은 주소). "답장 받을 메일" 칸을 미리 채우는 데만 쓴다 — 서버에 묻지 않는다.
/// 채우면 안 되는 주소는 null 이다([prefillReplyEmail]). 테스트는 이 provider 를 덮어쓴다.
final inquiryAccountEmailProvider = Provider<String?>((ref) {
  return prefillReplyEmail(Supabase.instance.client.auth.currentUser?.email);
});
