import 'dart:convert';
import 'dart:io';

/// 서버 시험과 같이 쓰는 입력 검사 표(`backend/tests/fixtures/input_rules_cases.json`)의 예시 목록.
/// 앱이 통과시키고 서버가 거절하면 가입이 막혀서 두 쪽 시험이 한 파일을 본다(보안 기준 2).
/// 경로는 `flutter test` 의 작업 폴더(frontend) 기준이다 — `code_lifetime_matches_supabase_test.dart` 와 같다.
List<String> inputRuleCases(String rule, String kind) {
  final file = File('../backend/tests/fixtures/input_rules_cases.json');
  final table = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return ((table[rule] as Map<String, dynamic>)[kind] as List<dynamic>).cast<String>();
}
