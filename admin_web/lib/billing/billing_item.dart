/// 결제 조회(A8) 데이터. 서버 모양은 backend/app/admin/billing.py 의 `_order` · `_day` · summary · shortfall.
/// 주문 번호(store_order_id)는 응답에 와도 읽지 않는다 — 모델 · 화면 상태에 남기지 않는다(대장 결정 8).
library;

import 'package:campus_mate_admin/widgets/status_badge.dart';

/// "₩1,284,000"
String formatWon(int won) {
  final digits = won.abs().toString();
  final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${won < 0 ? '-' : ''}₩$grouped';
}

/// 서버 월 "2026-10" → "2026년 10월"(앞의 0 은 뗀다)
String formatMonth(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  return '${parts[0]}년 ${int.tryParse(parts[1]) ?? parts[1]}월';
}

/// 서버 날짜 "2026-10-18" → "10/18". 한국 날짜 그대로 글자만 자른다(시간대 계산 없음).
String formatMonthDay(String date) {
  final parts = date.split('-');
  if (parts.length != 3) return date;
  return '${int.tryParse(parts[1]) ?? parts[1]}/${int.tryParse(parts[2]) ?? parts[2]}';
}

/// 구매 상태 → 배지(pen: 완료 success · 환불됨 danger · 그 밖 surface-strong + muted)
(String, StatusTone) purchaseStatusBadge(String status) {
  return switch (status) {
    'granted' => ('완료', StatusTone.success),
    'refunded' => ('환불됨', StatusTone.danger),
    _ => (status, StatusTone.neutral),
  };
}

/// 상품 이름: 상품 번호가 `heart_N` 이면 "하트 N개"(pen), 모르는 번호는 번호 글자 그대로
String productDisplayName(String productId) {
  final match = RegExp(r'^heart_(\d+)$').firstMatch(productId);
  return match == null ? productId : '하트 ${match.group(1)}개';
}

DateTime _time(Object? value) {
  final at = value is String ? DateTime.tryParse(value) : null;
  if (at == null) throw const FormatException('시각이 아니에요');
  return at;
}

/// 주문 번호로 찾은 구매 한 건
class BillingOrder {
  const BillingOrder({
    required this.store,
    required this.status,
    required this.productId,
    required this.grantedHearts,
    required this.clawedBackHearts,
    required this.purchasedAt,
    required this.refundedAt,
  });

  final String store;
  final String status;
  final String productId;
  final int grantedHearts;
  final int clawedBackHearts;
  final DateTime purchasedAt;
  final DateTime? refundedAt;

  String get productName => productDisplayName(productId);

  /// 결과 카드 "시각": 환불이면 환불 시각(못 거둔 표와 같은 값), 아니면 구매 시각
  DateTime get shownAt => status == 'refunded' ? refundedAt ?? purchasedAt : purchasedAt;

  static BillingOrder fromJson(Object? json) {
    if (json case {
      'store': final String store,
      'status': final String status,
      'product_id': final String productId,
      'granted_hearts': final int granted,
    }) {
      final clawed = json['clawed_back_hearts'];
      if (clawed is int?) {
        return BillingOrder(
          store: store,
          status: status,
          productId: productId,
          grantedHearts: granted,
          clawedBackHearts: clawed ?? 0,
          purchasedAt: _time(json['purchased_at']),
          refundedAt: json['refunded_at'] is String ? DateTime.tryParse(json['refunded_at'] as String) : null,
        );
      }
    }
    throw const FormatException('주문 한 건의 모양이 아니에요');
  }
}

class BillingSummary {
  const BillingSummary({required this.month, required this.revenueKrw});

  final String month;
  final int revenueKrw;

  static BillingSummary fromJson(Object? json) {
    if (json case {'month': final String month, 'revenue_krw': final int revenue}) {
      return BillingSummary(month: month, revenueKrw: revenue);
    }
    throw const FormatException('이번 달 매출의 모양이 아니에요');
  }
}

/// 하루 매출. [date] 는 서버가 준 한국 날짜 그대로("2026-10-18").
class DailyRevenue {
  const DailyRevenue({required this.date, required this.revenueKrw});

  final String date;
  final int revenueKrw;

  static DailyRevenue fromJson(Object? json) {
    if (json case {'date': final String date, 'revenue_krw': final int revenue}) {
      return DailyRevenue(date: date, revenueKrw: revenue);
    }
    throw const FormatException('일 매출 한 줄의 모양이 아니에요');
  }
}

/// 환불됐는데 하트를 다 못 거둔 구매 한 줄
class ShortfallRow {
  const ShortfallRow({
    required this.purchaseId,
    required this.nickname,
    required this.store,
    required this.productId,
    required this.grantedHearts,
    required this.clawedBackHearts,
    required this.shortfallHearts,
    required this.refundedAt,
  });

  final String purchaseId;
  final String? nickname;
  final String store;
  final String productId;
  final int grantedHearts;
  final int clawedBackHearts;
  final int shortfallHearts;
  final DateTime refundedAt;

  String get productName => productDisplayName(productId);

  static ShortfallRow fromJson(Object? json) {
    if (json case {
      'purchase_id': final String id,
      'store': final String store,
      'product_id': final String productId,
      'granted_hearts': final int granted,
      'clawed_back_hearts': final int clawed,
      'shortfall_hearts': final int shortfall,
    }) {
      final nickname = json['nickname'];
      if (nickname is String?) {
        return ShortfallRow(
          purchaseId: id,
          nickname: nickname,
          store: store,
          productId: productId,
          grantedHearts: granted,
          clawedBackHearts: clawed,
          shortfallHearts: shortfall,
          refundedAt: _time(json['refunded_at']),
        );
      }
    }
    throw const FormatException('못 거둔 하트 한 줄의 모양이 아니에요');
  }
}

/// 환불이 잦은 계정 한 줄(서버 `/admin/billing/frequent-returns`, DB 함수 admin_billing_returned_accounts — 시험 결제 · 지워진 계정 제외)
class ReturnedAccountRow {
  const ReturnedAccountRow({
    required this.profileId,
    required this.nickname,
    required this.refundCount,
    required this.refundedKrw,
    required this.grantedHearts,
    required this.clawedBackHearts,
    required this.shortfallHearts,
    required this.lastRefundedAt,
  });

  final String profileId;
  final String? nickname;
  final int refundCount;
  final int refundedKrw;
  final int grantedHearts;
  final int clawedBackHearts;
  final int shortfallHearts;
  final DateTime lastRefundedAt;

  static ReturnedAccountRow fromJson(Object? json) {
    if (json case {
      'profile_id': final String id,
      'refund_count': final int count,
      'refunded_krw': final int krw,
      'granted_hearts': final int granted,
      'clawed_back_hearts': final int clawed,
      'shortfall_hearts': final int shortfall,
    }) {
      final nickname = json['nickname'];
      if (nickname is String?) {
        return ReturnedAccountRow(
          profileId: id,
          nickname: nickname,
          refundCount: count,
          refundedKrw: krw,
          grantedHearts: granted,
          clawedBackHearts: clawed,
          shortfallHearts: shortfall,
          lastRefundedAt: _time(json['last_refunded_at']),
        );
      }
    }
    throw const FormatException('환불이 잦은 계정 한 줄의 모양이 아니에요');
  }
}
