/// 번호로 쪽을 나누는 목록의 한 쪽. [total] 은 같은 필터로 센 전체 건수(쪽 수는 화면이 쪽 크기로 나눈다).
class ListPage<T> {
  const ListPage({required this.items, required this.total});

  final List<T> items;
  final int total;

  /// 서버 `{"items": [...], "total": N, "page": p, "size": s}` 를 읽는다.
  static ListPage<T> fromJson<T>(Object? body, T Function(Object? row) parse, String what) {
    if (body case {'items': final List<Object?> rows, 'total': final int total}) {
      return ListPage(items: [for (final row in rows) parse(row)], total: total);
    }
    throw FormatException('$what 의 모양이 아니에요');
  }
}

/// 전체 [total] 건을 [size] 씩 나눈 마지막 쪽(0건이어도 1쪽)
int lastPage(int total, int size) => total <= 0 ? 1 : (total + size - 1) ~/ size;
