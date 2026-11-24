/// 쪽 넘김 커서 — **서버에서 받은** 끝 줄의 시각과 id. 피드(`before` · `before_id`) · 댓글(`after` · `after_id`)이 같이 쓴다.
/// 시각만 보내면 같은 시각에 올라간 두 줄이 쪽 경계에서 하나 빠지고, 하나만 보내면 서버가 422 로 막는다 — 그래서 늘 짝이다.
typedef PageCursor = ({DateTime createdAt, String id});

extension PageCursorQuery on PageCursor {
  /// `{key: 시각(UTC), key_id: id}`.
  Map<String, String> toQuery(String key) => {key: createdAt.toUtc().toIso8601String(), '${key}_id': id};
}

/// 서버의 한 쪽 `{items, has_more}`. 피드(투표 · 게시물) · 댓글이 같은 모양이다.
class FeedPage<T> {
  const FeedPage({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;

  factory FeedPage.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parseItem) {
    return FeedPage(
      items: [for (final item in json['items'] as List<dynamic>) parseItem(item as Map<String, dynamic>)],
      hasMore: json['has_more'] as bool,
    );
  }
}
