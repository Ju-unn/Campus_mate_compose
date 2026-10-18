/// 커서로 쪽을 나누는 목록(매칭 · 작업 기록) 한 쪽. [nextBefore] 가 null 이면 마지막 쪽이다.
class CursorPage<T> {
  const CursorPage({required this.items, required this.nextBefore});

  final List<T> items;
  final String? nextBefore;

  /// 서버 `{"items": [...], "next_before": "…" | null}` 를 읽는다.
  static CursorPage<T> fromJson<T>(Object? body, T Function(Object? row) parse, String what) {
    if (body case {'items': final List<Object?> rows}) {
      final next = body['next_before'];
      if (next is String?) return CursorPage(items: [for (final row in rows) parse(row)], nextBefore: next);
    }
    throw FormatException('$what 의 모양이 아니에요');
  }
}
