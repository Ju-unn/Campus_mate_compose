import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 화면 3c 의 "학교 확인" 행에 보여줄 학교명.
///
/// 읽기 전용이고 RLS(`profiles are readable by owner`)가 본인 행만 열어주므로
/// FastAPI 를 거치지 않고 Supabase 에서 바로 읽는다(2026-09-19 Task A12 결정).
/// 남의 데이터가 섞일 수 없어 설계 §7.1 "FastAPI 경유" 원칙의 적용 대상이 아니다.
/// 정책이 본인 행 하나만 남기므로 `id` 필터를 따로 걸지 않는다.
final schoolNameProvider = FutureProvider<String>((ref) async {
  final profiles = Supabase.instance.client.from('profiles');
  final row = await profiles.select('universities(name)').single();
  final university = row['universities']! as Map<String, dynamic>;
  return university['name']! as String;
});
