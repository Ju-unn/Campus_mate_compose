import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 15b 시트에서 고른 것. 취소 · 바깥 누름은 null.
enum AvatarRegenChoice { regenerate, chargeHearts }

/// 15b(pen `aGaPA`) · 15b-2 무료(`N5lXcc`) · 15b-3 하트 모자람(`i8rkW`). 취소 · 바깥 누름이면 null.
///
/// [cost] · [heartBalance] 는 서버 값(`avatar_regen_cost` · `heart_balance`)이다 — 앱에 10 을 박지 않는다.
/// 틀은 안전 시트와 같다(계획서 C4 — common 으로 빼지 않는다).
Future<AvatarRegenChoice?> showAvatarRegenSheet(
  BuildContext context, {
  required int cost,
  required int heartBalance,
}) {
  return showSafetySheet<AvatarRegenChoice>(
    context,
    (_) => _AvatarRegenSheet(cost: cost, heartBalance: heartBalance),
  );
}

class _AvatarRegenSheet extends StatelessWidget {
  const _AvatarRegenSheet({required this.cost, required this.heartBalance});

  final int cost;
  final int heartBalance;

  @override
  Widget build(BuildContext context) {
    final (title, description, cta) = _content();
    return SafetySheet(
      children: [
        // pen `Fgqkt` 20/700, 줄높이 속성 없음 · 렌더 29.
        Text(title, style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
        const SizedBox(height: AppSpacing.md),
        // pen `Ra0he` 16 / body / 1.5.
        Text(description, style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5)),
        // pen 은 설명과 버튼 사이에 투명 4(`RAC9j`)를 끼워 16 + 4 + 16 = 36 을 만든다.
        const SizedBox(height: 36),
        cta,
        const SizedBox(height: AppSpacing.md),
        SafetySheetButton.neutral(label: '취소', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  /// 세 모양 가르기. 무료 차례가 먼저다 — 무료면 잔액이 0 이어도 만들 수 있다.
  (String, String, Widget) _content() {
    if (cost == 0) {
      return (
        '아바타를 다시 만들까요?',
        '첫 번째 다시 만들기는 무료예요. 새 아바타는 바로 프로필에 반영돼요.',
        const _ChoiceButton(label: '무료로 만들기', choice: AvatarRegenChoice.regenerate),
      );
    }
    if (heartBalance < cost) {
      // 제목은 서버 HEARTS_NOT_ENOUGH 와 같은 글(계획서 C8).
      return (
        '하트가 모자라요',
        '하트 $cost개가 필요해요. 지금 보유한 하트는 $heartBalance개예요.',
        const _ChoiceButton(label: '하트 충전하기', choice: AvatarRegenChoice.chargeHearts, heart: _HeartGlyph()),
      );
    }
    return (
      '아바타를 다시 만들까요?',
      '하트 $cost개가 차감돼요. 지금 보유한 하트는 $heartBalance개예요. 새 아바타는 바로 프로필에 반영돼요.',
      _ChoiceButton(label: '$cost 쓰고 만들기', choice: AvatarRegenChoice.regenerate, heart: const _HeartGlyph()),
    );
  }
}

/// 주색 CTA(pen `wf0b2` 320×52). 누르면 [choice] 를 돌려주며 닫는다.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.label, required this.choice, this.heart});

  final String label;
  final AvatarRegenChoice choice;
  final _HeartGlyph? heart;

  @override
  Widget build(BuildContext context) {
    return SafetySheetButton.primary(
      label: label,
      leading: heart,
      onPressed: () => Navigator.of(context).pop(choice),
    );
  }
}

/// 주색 채움 위 재화 하트(pen `n3D3iC` 26×26, DESIGN §8.3 on-primary 변형).
/// 화면 읽기에서는 뺀다 — 버튼 안에 두면 버튼과 따로 떨어진 노드가 되어 "…버튼", "하트" 로 두 번 멈춘다.
/// 단위는 바로 위 설명("하트 10개가 차감돼요" · "하트 10개가 필요해요")이 이미 읽어 준다.
class _HeartGlyph extends StatelessWidget {
  const _HeartGlyph();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/heart-flat-vector-on-primary-v1.png',
      width: 26,
      height: 26,
      excludeFromSemantics: true,
    );
  }
}
