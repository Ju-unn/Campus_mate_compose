import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 학교 이름 → 로고 주소(공개 버킷 `university-logos`). 학교 줄이 이름으로 찾고, 없으면 이름만 그린다.
///
/// FastAPI 를 거치지 않고 Supabase 에서 바로 읽는다. `universities` 는 anon · authenticated 전체 읽기인
/// 공개 참조 표다(20260913054542) — 개인정보도 남의 데이터도 없다. 앱이 켜져 있는 동안 한 번만 읽는다 —
/// 실패하면 Riverpod 이 다시 시도하고(기본 10번), 그동안 학교 줄은 이름만 그린다.
final universityLogosProvider = FutureProvider<Map<String, String>>(
  (ref) => fetchUniversityLogos(Supabase.instance.client),
);

Future<Map<String, String>> fetchUniversityLogos(SupabaseClient client) async {
  final rows = await client.from('universities').select('name,logo_path');
  final bucket = client.storage.from('university-logos');
  return {
    for (final row in rows)
      if (row['logo_path'] case final String path) row['name'] as String: bucket.getPublicUrl(path),
  };
}
