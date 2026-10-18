/// 사용자(A5) 데이터. 서버 모양은 backend/app/admin/users.py 의 `_summary` · `get_user` · user_actions.py.
/// 서버 글자(닉네임 · 메모)는 손대지 않고 그대로 들고 있다 — 화면은 일반 Text 로만 그린다.
library;

import 'package:campus_mate_admin/billing/billing_item.dart' show productDisplayName;
import 'package:campus_mate_admin/widgets/status_badge.dart';

/// 프로필 상태 → 배지(pen: 승인 success · 정지 danger · 탈퇴 neutral). 가입 중은 pen 에 없어 warning.
(String, StatusTone) userStatusBadge(String status) {
  return switch (status) {
    'active' => ('승인', StatusTone.success),
    'suspended' => ('정지', StatusTone.danger),
    'withdrawn' => ('탈퇴', StatusTone.neutral),
    'pending' => ('가입 중', StatusTone.warning),
    _ => (status, StatusTone.neutral),
  };
}

/// 로그인 방식 코드(auth identities provider) → 배지 글자 · 본인 확인 줄 글자. 모르는 값은 그대로.
String loginProviderName(String provider) {
  return switch (provider) {
    'kakao' => '카카오',
    'google' => '구글',
    'apple' => '애플',
    _ => provider,
  };
}

/// 하트 원장 종류(heart_reason enum, 마이그레이션 20260920043832 · 20261013010000). pen 예시는 "무료 인증샷 보상" · "카드 열기".
String heartReasonLabel(String reason) {
  return switch (reason) {
    'purchase' => '하트 구매',
    'referral' => '추천 보상',
    'promo' => '프로모션',
    'free_task' => '무료 인증샷 보상',
    'poll_vote' => '투표 참여',
    'extra_card' => '카드 열기',
    'avatar_regen' => '아바타 다시 만들기',
    'refund' => '환불 회수',
    'admin_adjust' => '관리자 조정',
    'first_purchase_bonus' => '첫 구매 보너스',
    _ => reason,
  };
}

/// 스토어 코드(store_platform enum) → 글자(pen: 구글 플레이 · 앱스토어)
String storeName(String store) {
  return switch (store) {
    'play_store' => '구글 플레이',
    'app_store' => '앱스토어',
    _ => store,
  };
}

/// "yyyy-MM-dd"(한국 시간 날짜)
String formatKstDate(DateTime at) {
  final kst = at.toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${kst.year}-${two(kst.month)}-${two(kst.day)}';
}

/// 프로필 id 줄임(pen: "8f3a…c21") — 앞 4 + … + 뒤 3
String shortProfileId(String id) => id.length <= 8 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 3)}';

DateTime _time(Object? value, String what) {
  final at = value is String ? DateTime.tryParse(value) : null;
  if (at == null) throw FormatException('$what 시각이 아니에요');
  return at;
}

DateTime? _timeOrNull(Object? value) => value is String ? DateTime.tryParse(value) : null;

/// 목록 한 줄(UserSummary). 가입 중이면 닉네임 · 학교가 null.
class UserSummary {
  const UserSummary({
    required this.id,
    required this.nickname,
    required this.university,
    required this.status,
    required this.createdAt,
    required this.reportCount,
  });

  final String id;
  final String? nickname;
  final String? university;
  final String status;
  final DateTime createdAt;

  /// 그 사람이 받은 신고 수
  final int reportCount;

  bool get isSuspended => status == 'suspended';
  bool get isWithdrawn => status == 'withdrawn';

  /// 정지할 수 있는 상태(DB 함수가 pending · active 만 정지한다 — 신고 상세와 같은 규칙)
  bool get canSuspend => status == 'active' || status == 'pending';

  static UserSummary fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'status': final String status,
      'report_count': final int reports,
    }) {
      final nickname = json['nickname'];
      final university = json['university'];
      if (nickname is String? && university is String?) {
        return UserSummary(
          id: id,
          nickname: nickname,
          university: university,
          status: status,
          createdAt: _time(json['created_at'], '가입'),
          reportCount: reports,
        );
      }
    }
    throw const FormatException('사용자 한 줄의 모양이 아니에요');
  }
}

/// 하트 원장 한 줄 — [balanceAfter] 는 그 줄 직후 잔액(서버가 거슬러 계산)
class HeartEntry {
  const HeartEntry({required this.id, required this.createdAt, required this.amount, required this.reason, required this.balanceAfter});

  final String id;
  final DateTime createdAt;
  final int amount;
  final String reason;
  final int balanceAfter;

  static HeartEntry fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'amount': final int amount,
      'reason': final String reason,
      'balance_after': final int balance,
    }) {
      return HeartEntry(id: id, createdAt: _time(json['created_at'], '원장'), amount: amount, reason: reason, balanceAfter: balance);
    }
    throw const FormatException('하트 원장 한 줄의 모양이 아니에요');
  }
}

/// 구매 한 줄. 주문 번호 · 토큰은 서버가 싣지 않는다.
class PurchaseEntry {
  const PurchaseEntry({
    required this.id,
    required this.store,
    required this.status,
    required this.isTest,
    required this.grantedHearts,
    required this.productId,
    required this.purchasedAt,
  });

  final String id;
  final String store;
  final String status;
  final bool isTest;
  final int grantedHearts;
  final String productId;
  final DateTime purchasedAt;

  /// 상품 이름(pen "하트 100개") — `heart_N` 이면 그대로 풀고 모르는 번호는 번호 글자
  String get productName => productDisplayName(productId);

  /// 표 "상태" 글자(pen: 완료 · 환불). 모르는 값은 그대로.
  String get statusLabel => switch (status) {
    'granted' => '완료',
    'refunded' => '환불',
    _ => status,
  };

  static PurchaseEntry fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'store': final String store,
      'status': final String status,
      'is_test': final bool isTest,
      'granted_hearts': final int granted,
      'product_id': final String productId,
    }) {
      return PurchaseEntry(
        id: id,
        store: store,
        status: status,
        isTest: isTest,
        grantedHearts: granted,
        productId: productId,
        purchasedAt: _time(json['purchased_at'], '구매'),
      );
    }
    throw const FormatException('구매 한 줄의 모양이 아니에요');
  }
}

/// 메모 한 줄. 쓴 관리자는 번호뿐이라(서버) 화면에는 "admin" 으로 적는다.
class UserNote {
  const UserNote({required this.id, required this.createdAt, required this.text});

  final String id;
  final DateTime createdAt;
  final String text;

  static UserNote fromJson(Object? json) {
    if (json case {'id': final String id, 'text': final String text}) {
      return UserNote(id: id, createdAt: _time(json['created_at'], '메모'), text: text);
    }
    throw const FormatException('메모 한 줄의 모양이 아니에요');
  }
}

/// 상세(UserDetail)
class UserDetail {
  const UserDetail({
    required this.summary,
    required this.lastActiveAt,
    required this.avatarUrl,
    required this.loginProviders,
    required this.heartBalance,
    required this.contactBlockCount,
    required this.hearts,
    required this.purchases,
    required this.notes,
  });

  final UserSummary summary;
  final DateTime? lastActiveAt;

  /// 공개 아바타 주소(없으면 사람 모양 아이콘 자리)
  final String? avatarUrl;

  /// 로그인 방식들(kakao · google · apple). 서버가 못 알아냈으면 null.
  final List<String>? loginProviders;
  final int heartBalance;
  final int contactBlockCount;
  final List<HeartEntry> hearts;
  final List<PurchaseEntry> purchases;
  final List<UserNote> notes;

  static UserDetail fromJson(Object? json) {
    if (json case {
      'heart_balance': final int balance,
      'contact_block_count': final int blocks,
      'hearts': final List<Object?> hearts,
      'purchases': final List<Object?> purchases,
      'notes': final List<Object?> notes,
    }) {
      final providers = json['login_providers'];
      final avatar = json['avatar_url'];
      if (providers is List<Object?>? && avatar is String?) {
        return UserDetail(
          summary: UserSummary.fromJson(json),
          lastActiveAt: _timeOrNull(json['last_active_at']),
          avatarUrl: avatar,
          loginProviders: providers == null ? null : [for (final p in providers) if (p is String) p],
          heartBalance: balance,
          contactBlockCount: blocks,
          hearts: [for (final row in hearts) HeartEntry.fromJson(row)],
          purchases: [for (final row in purchases) PurchaseEntry.fromJson(row)],
          notes: [for (final row in notes) UserNote.fromJson(row)],
        );
      }
    }
    throw const FormatException('사용자 상세의 모양이 아니에요');
  }
}

/// 열람 결과. 값은 열람 대화상자 State 에만 두고 닫으면 버린다(전역 provider · 캐시 금지).
/// `toString` 은 값을 싣지 않는다 — 실수로 로그에 찍혀도 새지 않게.
class PrivateContact {
  const PrivateContact({required this.phoneNumber, required this.kakaoId});

  final String? phoneNumber;
  final String? kakaoId;

  static PrivateContact fromJson(Object? json) {
    if (json case {'phone_number': final String? phone, 'kakao_id': final String? kakao}) {
      return PrivateContact(phoneNumber: phone, kakaoId: kakao);
    }
    throw const FormatException('열람 결과의 모양이 아니에요');
  }

  @override
  String toString() => 'PrivateContact(…)';
}

/// 탈퇴 대행 결과. 바깥 정리(cleanup)가 어디서 실패했는지만 든다.
class CloseAccountResult {
  const CloseAccountResult({required this.kakaoUnlinkFailed, required this.otherCleanupFailed});

  /// 카카오 연결 끊기 실패(`kakao_unlink == "failed"`; 카카오 가입이 아니면 skipped)
  final bool kakaoUnlinkFailed;

  /// 푸시 토큰 · 인증 파일 정리 실패
  final bool otherCleanupFailed;

  static CloseAccountResult fromJson(Object? json) {
    if (json case {'cleanup': final Map<Object?, Object?> cleanup}) {
      return CloseAccountResult(
        kakaoUnlinkFailed: cleanup['kakao_unlink'] == 'failed',
        otherCleanupFailed: cleanup['push_tokens'] == 'failed' || cleanup['student_id_files'] == 'failed',
      );
    }
    throw const FormatException('탈퇴 대행 결과의 모양이 아니에요');
  }
}
