import 'package:campus_mate/tour/model/tour_seen_store.dart';

/// 메모리에만 두는 가짜. [seen] 에 미리 넣어 두면 그 계정은 이미 본 것이다. [failing] 이면 읽기가 실패한다.
class FakeTourSeenStore implements TourSeenStore {
  FakeTourSeenStore({Set<String>? seen, this.failing = false}) : seen = seen ?? <String>{};

  final Set<String> seen;
  final bool failing;

  /// 본 것으로 저장한 계정 id(순서대로).
  final List<String> marked = [];

  @override
  Future<bool> hasSeen(String profileId) async {
    if (failing) throw StateError('저장소를 못 엶');
    return seen.contains(profileId);
  }

  @override
  Future<void> markSeen(String profileId) async {
    marked.add(profileId);
    seen.add(profileId);
  }
}
