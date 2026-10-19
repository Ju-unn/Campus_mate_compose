/// 인증샷 검수(A3) 데이터. 서버 모양은 backend/app/admin/heart_task_review.py 의 `_summary` · `_item`.
library;

/// 하트 작업 항목. 글자는 계획서 Global Constraints — 목록 줄은 짧게, 정보 카드는 길게.
enum HeartTaskKind {
  everytimePost('everytime_post', '에브리타임', '에브리타임 홍보'),
  kakaoShare('kakao_share', '단톡방', '단톡방 공유');

  const HeartTaskKind(this.code, this.listLabel, this.infoLabel);

  final String code;
  final String listLabel;
  final String infoLabel;

  static HeartTaskKind? fromCode(String code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// 반려 사유 3개(enum public.heart_task_reject_reason). 글자는 앱 frontend/lib/billing/model/heart_task.dart 와 같다.
enum HeartTaskRejectReason {
  dateMissing('date_missing', '날짜가 안 보여요'),
  notVerified('not_verified', '게시글·공유가 확인되지 않아요'),
  reused('reused', '이미 쓴 캡처예요');

  const HeartTaskRejectReason(this.code, this.label);

  final String code;
  final String label;
}

/// 목록 한 줄 — 사진 · 지난 제출이 없는 요약(서버가 목록에서는 서명하지 않는다).
class HeartTaskItem {
  const HeartTaskItem({
    required this.id,
    required this.kind,
    required this.nickname,
    required this.university,
    required this.rewardHearts,
    required this.createdAt,
  });

  final String id;
  final HeartTaskKind kind;
  final String nickname;
  final String university;
  final int rewardHearts;
  final DateTime createdAt;

  static HeartTaskItem fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'task': final String task,
      'reward_hearts': final int reward,
      'created_at': final String createdAt,
      'profile': {'nickname': final String? nickname, 'university': final String university},
    }) {
      final kind = HeartTaskKind.fromCode(task);
      final at = DateTime.tryParse(createdAt);
      if (kind != null && at != null) {
        return HeartTaskItem(
          id: id,
          kind: kind,
          // 가입을 마치기 전 프로필이면 닉네임이 비어 있을 수 있다(profiles.nickname null 허용)
          nickname: nickname ?? '—',
          university: university,
          rewardHearts: reward,
          createdAt: at,
        );
      }
    }
    throw const FormatException('인증샷 제출 한 줄의 모양이 아니에요');
  }
}

/// 사진 주소 목록 읽기. 새 서버는 `photo_urls`(사진 순서, 서명에 실패한 장은 null)를, 옛 서버는 첫 장 `photo_url` 하나만 준다.
/// `photo_urls` 가 있으면 그것을, 없으면 `photo_url` 하나짜리 목록(null 이면 빈 목록)을 쓴다 — 웹이 서버보다 먼저 나가도 죽지 않는다.
/// 둘 다 없거나 모양이 틀리면 null(호출한 쪽이 FormatException).
List<String?>? _readPhotoUrls(Map<Object?, Object?> json) {
  final urls = json['photo_urls'];
  if (urls != null) {
    if (urls is List<Object?> && urls.every((u) => u == null || u is String)) return [for (final u in urls) u as String?];
    return null;
  }
  if (json.containsKey('photo_url')) {
    return switch (json['photo_url']) {
      null => const <String?>[],
      final String url => [url],
      _ => null,
    };
  }
  return null;
}

/// 같은 사람 · 같은 항목의 지난 제출 하나(사진이 남은 것만, 최근 순 최대 5)
class HeartTaskPrevious {
  const HeartTaskPrevious({required this.id, required this.status, required this.createdAt, required this.photoUrls});

  final String id;
  final String status;
  final DateTime createdAt;

  /// 5분 서명 주소들(사진 순서). 서명에 실패한 장은 null.
  final List<String?> photoUrls;

  /// 지난 제출 줄은 1장씩 보인다(pen A3 "지난 제출 (사진 1장씩)") — 서명에 실패해 비어 있는 장은 건너뛴 첫 장의 자리(0부터).
  /// 모두 없으면 null("사진 없음").
  int? get photoIndex {
    final index = photoUrls.indexWhere((url) => url != null);
    return index < 0 ? null : index;
  }

  /// [photoIndex] 장의 5분 서명 주소
  String? get photoUrl => photoUrls.nonNulls.firstOrNull;

  static HeartTaskPrevious fromJson(Object? json) {
    if (json is Map<Object?, Object?>) {
      final photoUrls = _readPhotoUrls(json);
      if (json case {'id': final String id, 'status': final String status, 'created_at': final String createdAt} when photoUrls != null) {
        final at = DateTime.tryParse(createdAt);
        if (at != null) return HeartTaskPrevious(id: id, status: status, createdAt: at, photoUrls: photoUrls);
      }
    }
    throw const FormatException('지난 제출의 모양이 아니에요');
  }
}

/// 한 건(고른 줄 · 디스코드 링크) — 요약 + 지금 상태 + 5분 서명 사진 + 지난 제출.
class HeartTaskDetail {
  const HeartTaskDetail({required this.item, required this.status, required this.photoUrls, required this.previous});

  final HeartTaskItem item;
  final String status;

  /// 사진 순서대로 5분 서명 주소. 서명에 실패한 장은 null("사진 없음"), 60일 정리로 경로가 비면 빈 목록.
  final List<String?> photoUrls;
  final List<HeartTaskPrevious> previous;

  /// 첫 장(옛 호출부용)
  String? get photoUrl => photoUrls.firstOrNull;

  /// 아직 아무도 처리하지 않았다
  bool get isWaiting => status == 'submitted';

  static HeartTaskDetail fromJson(Object? json) {
    final photoUrls = json is Map<Object?, Object?> ? _readPhotoUrls(json) : null;
    if (json case {'status': final String status, 'previous': final List<Object?> previous} when photoUrls != null) {
      return HeartTaskDetail(
        item: HeartTaskItem.fromJson(json),
        status: status,
        photoUrls: photoUrls,
        previous: [for (final p in previous) HeartTaskPrevious.fromJson(p)],
      );
    }
    throw const FormatException('인증샷 제출 한 건의 모양이 아니에요');
  }
}

/// 한국 시간(UTC+9, 서머타임 없음) `YYYY-MM-DD HH:mm` — 정보 카드 "제출 시각"
String formatSubmittedAt(DateTime at) {
  final kst = at.toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${kst.year}-${two(kst.month)}-${two(kst.day)} ${two(kst.hour)}:${two(kst.minute)}';
}

/// 목록 줄의 지난 시간: 1시간 안은 "n분 전", 하루 안은 "n시간 전", 그 뒤는 "n일 전".
/// 1분 안은 "0분 전"(대장 지시의 세 꼴만 쓴다). 시계가 어긋나 미래 시각이면 0 으로 본다.
String formatAgo(DateTime at, DateTime now) {
  final passed = now.difference(at);
  if (passed.inMinutes < 60) return '${passed.isNegative ? 0 : passed.inMinutes}분 전';
  if (passed.inHours < 24) return '${passed.inHours}시간 전';
  return '${passed.inDays}일 전';
}

String formatReward(int hearts) => '하트 $hearts개';
