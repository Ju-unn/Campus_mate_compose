import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 09b 메인이 읽는 요약. 못 받으면 null 이고 화면은 요약 섹션만 비운다.
/// 실패를 던지지 않는다 — 던지면 Riverpod 3 이 알아서 재시도 타이머를 건다.
final homeSummaryProvider = FutureProvider<HomeSummary?>((ref) async {
  final result = await ref.watch(homeRepositoryProvider).fetchSummary();
  return result.when(onSuccess: (summary) => summary, onFailure: (_) => null);
});
