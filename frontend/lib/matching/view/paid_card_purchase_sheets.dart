import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/view/paid_card_locked.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 결제 카드를 열기 전 확인 시트. 열기로 했으면 true, 취소 · 바깥 누름 · 스와이프는 false.
///
/// 구조는 pen `x2yPl`(세로 gap 16, padding [12,20,28,20], 위 모서리 24, 제목 20/700, 설명 16/1.5 #3F3F3F, 주 버튼 320×52 + 하트)
/// 그대로이고, **문구만 지시문 23 D 의 초안**이다(사용자 확정 전). pen 의 FAQ 칸(`Ma6Ms`)은 뜻이 정해지지 않아 옮기지 않았다.
/// [heartBalance] 가 null(읽는 중 · 실패)이면 잔액 문장을 뺀다 — 틀린 숫자를 말하지 않는다.
Future<bool> showPaidCardConfirmSheet(
  BuildContext context, {
  required int cost,
  required int? heartBalance,
}) async {
  final confirmed = await showSafetySheet<bool>(
    context,
    (_) => _PaidCardSheet(
      title: '이 사람을 지금 열어 볼까요?',
      description: '하트 $cost개가 차감돼요. ${_balanceSentence(heartBalance)}'
          '한 번에 한 명만 열 수 있고, 산 카드는 결정할 때까지 사라지지 않아요.',
      primaryLabel: '$cost 쓰고 열기',
      primaryHasHeart: true,
      secondaryLabel: '취소',
    ),
  );
  return confirmed ?? false;
}

/// 열기가 402(하트 부족)로 막혔을 때의 시트. 하트 스토어로 가려면 true, 닫기 · 바깥 누름은 false.
/// 제목은 서버 HEARTS_NOT_ENOUGH 와 같은 글자다. pen 에 전용 시트가 없어(값표 §8) 확인 시트와 같은 틀을 쓴다.
Future<bool> showPaidCardHeartsShortSheet(
  BuildContext context, {
  required int cost,
  required int? heartBalance,
}) async {
  final goToStore = await showSafetySheet<bool>(
    context,
    (_) => _PaidCardSheet(
      title: '하트가 모자라요',
      description: '하트 $cost개가 필요해요.${_balanceSentence(heartBalance, leadingSpace: true)}',
      primaryLabel: '하트 스토어로 가기',
      primaryHasHeart: false,
      secondaryLabel: '닫기',
    ),
  );
  return goToStore ?? false;
}

/// "지금 보유한 하트는 N개예요." — 잔액을 모르면 빈 글자.
String _balanceSentence(int? heartBalance, {bool leadingSpace = false}) {
  if (heartBalance == null) {
    return '';
  }
  return leadingSpace ? ' 지금 보유한 하트는 $heartBalance개예요.' : '지금 보유한 하트는 $heartBalance개예요. ';
}

class _PaidCardSheet extends StatelessWidget {
  const _PaidCardSheet({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.primaryHasHeart,
    required this.secondaryLabel,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final bool primaryHasHeart;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return SafetySheet(
      children: [
        // pen `GZRVW` 20/700 #222222, 줄높이 속성 없음 · 렌더 29.
        Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
        const SizedBox(height: AppSpacing.md),
        // pen `g5RAq0` 16/400/1.5 #3F3F3F.
        Text(description, style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5)),
        // pen 은 설명과 버튼 사이에 투명 4(`keBbl`)를 끼워 16 + 4 + 16 = 36.
        const SizedBox(height: 36),
        SafetySheetButton.primary(
          label: primaryLabel,
          leading: primaryHasHeart ? const PaidCardHeart() : null,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: secondaryLabel, onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
