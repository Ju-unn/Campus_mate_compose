import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 재화 하트 글리프 — 주색 채움 위용(pen `AJDbc` 26×26, DESIGN §5.4). 버튼이 이미 "N으로 열기" 로 읽히니 낭독에서는 뺀다.
const String paidCardHeartAsset = 'assets/images/heart-flat-vector-on-primary-v1.png';

/// 결제 카드(잠금 카드) 마스터 `qoYnh` · 328×368 (지시문 23 B, pen 값표 §1).
/// 미리 정해진 한 사람의 아바타를 **흐림 + 자물쇠** 로만 보여 주고, 맞는 이유 태그와 "N으로 열기" 버튼을 둔다.
///
/// 이름 · 학교 · 나이 같은 칸은 서버가 아예 안 주고, 앱도 점수 · 순위 숫자 · 비중을 그리지 않는다.
/// 위치의 기준은 카드 바깥 가장자리다: pen 의 stroke 는 안쪽에 그려져 padding 20 이 stroke 를 포함한다 —
/// 그래서 [Container] 가 아니라 [DecoratedBox] 로 테두리를 칠한다([Container] 는 테두리 두께만큼 padding 을 더 준다).
class PaidCardLocked extends StatelessWidget {
  const PaidCardLocked({
    required this.card,
    required this.onOpen,
    required this.onInfo,
    this.busy = false,
    super.key,
  });

  final PaidCardOffered card;

  /// "N으로 열기" 를 눌렀다. 확인 시트는 부른 쪽이 띄운다.
  final VoidCallback onOpen;

  /// 물음표를 눌렀다("이렇게 정밀하게 골랐어요" 안내 시트).
  final VoidCallback onInfo;

  /// 열기 요청이 가 있는 동안 true — 버튼을 잠근다.
  final bool busy;

  /// 카드 안 세로 간격 14(pen gap). 간격 토큰 sm(12)·md(16) 사이 값이다.
  static const double _gap = 14;

  /// 물음표 `MHRC6`: 보이는 그림 22, 눌림 칸 48. pen 은 보이는 그림의 왼쪽 위를 (290,16) 에 둔다.
  static const double _infoVisible = 22;
  static const double _infoTouch = 48;
  static const double _infoLeft = 290;
  static const double _infoTop = 16;

  /// 이유 태그 최대 개수(서버도 3개까지만 준다).
  static const int _maxReasons = 3;

  @override
  Widget build(BuildContext context) {
    final reasons = card.reasons.take(_maxReasons).toList();
    // 눌림 칸을 보이는 그림 가운데에 맞춘다: 290 - (48-22)/2 = 277, 16 - 13 = 3.
    const inset = (_infoTouch - _infoVisible) / 2;
    return Stack(
      children: [
        DecoratedBox(
          key: const ValueKey('paid-card-frame'),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.hairlineSoft),
            // pen 그림자 (0,2) blur 8 #1A16190A / (0,8) blur 20 #1A16190F = cardSoft.
            boxShadow: AppElevation.cardSoft,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _MosaicAvatar(url: card.avatarUrl)),
                const SizedBox(height: _gap),
                _Headline(bandCount: card.bandCount),
                if (reasons.isNotEmpty) ...[
                  const SizedBox(height: _gap),
                  _ReasonTags(reasons: reasons),
                ],
                const SizedBox(height: _gap),
                KeyedSubtree(
                  key: const ValueKey('paid-card-open'),
                  child: SafetySheetButton.primary(
                    label: '${card.cost}으로 열기',
                    leading: const PaidCardHeart(),
                    onPressed: busy ? null : onOpen,
                  ),
                ),
                const SizedBox(height: _gap),
                const _Caption(),
              ],
            ),
          ),
        ),
        Positioned(
          left: _infoLeft - inset,
          top: _infoTop - inset,
          width: _infoTouch,
          height: _infoTouch,
          child: _InfoButton(onTap: onInfo),
        ),
      ],
    );
  }
}

/// 주색 버튼 안 하트(26×26). 확인 시트의 "N 쓰고 열기" 버튼도 같은 그림을 쓴다.
class PaidCardHeart extends StatelessWidget {
  const PaidCardHeart({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(paidCardHeartAsset, width: 26, height: 26, excludeFromSemantics: true);
  }
}

/// `FLFiL` 88×88 원. 사진은 **반드시 blur 를 입힌 채로만** 그린다 — 자리를 채우는 동안 · 실패했을 때는 회색 원이다.
/// 공개 저장소 주소라서 흐림은 앱의 몫이다(서버 계약의 알려진 한계). 낭독기에는 읽히지 않게 한다.
class _MosaicAvatar extends StatelessWidget {
  const _MosaicAvatar({required this.url});

  final String? url;

  /// pen `q758n6` blur 반지름 10.
  static const double _blur = 10;

  static const DecoratedBox _fallback = DecoratedBox(
    key: ValueKey('paid-card-avatar-fallback'),
    decoration: BoxDecoration(color: AppColors.surfaceStrong),
  );

  @override
  Widget build(BuildContext context) {
    final photo = url;
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('paid-card-avatar'),
        width: 88,
        height: 88,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (photo == null)
                _fallback
              else
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
                  child: CachedNetworkImage(
                    key: const ValueKey('paid-card-photo'),
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _fallback,
                    errorWidget: (context, url, error) => _fallback,
                  ),
                ),
              const Center(child: _LockCircle()),
            ],
          ),
        ),
      ),
    );
  }
}

/// `DMOuj` 36×36 흰색 80% 원 + lock 18. 아바타 가운데(26,26)에 앉는다.
class _LockCircle extends StatelessWidget {
  const _LockCircle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('paid-card-lock'),
      width: 36,
      height: 36,
      child: DecoratedBox(
        // pen #FFFFFFCC = 흰색 80%.
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.canvas.withValues(alpha: 0.8)),
        child: const Center(child: Icon(AppIcons.lock, size: 18, color: AppColors.ink)),
      ),
    );
  }
}

/// `H7ko9` 17/600/1.45 가운데. 두 줄이 pen 에서 52 칸이라 그보다 작아지지 않고, 글자를 키우면 따라 커진다.
class _Headline extends StatelessWidget {
  const _Headline({required this.bandCount});

  final int bandCount;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: const ValueKey('paid-card-headline'),
      constraints: const BoxConstraints(minHeight: 52),
      child: Text(
        '나와 성향이 잘 맞는 사람\n$bandCount명이 기다리고 있어요',
        textAlign: TextAlign.center,
        style: AppTypography.subtitle.copyWith(color: AppColors.ink),
      ),
    );
  }
}

/// `oAdfz` — 한 줄에 들어가는 만큼 가운데로 줄바꿈, 태그 사이 6 · 행 사이 6.
class _ReasonTags extends StatelessWidget {
  const _ReasonTags({required this.reasons});

  final List<ReasonTag> reasons;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [for (final reason in reasons) _ReasonTagPill(text: reason.text)],
    );
  }
}

/// `HYMM2` — 가로 padding 11, 높이 28, pill. 카드 안에서는 채움 #FFFFFF + 테두리 1 #EBEBEB 로 덮어쓴다(pen `O9qBm0`).
/// 글자 12/400 #3F3F3F, 줄간격 속성 없음 · 렌더 17.
class _ReasonTagPill extends StatelessWidget {
  const _ReasonTagPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey('reason-tag:$text'),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Center(
            widthFactor: 1,
            child: Text(text, style: AppTypography.caption.copyWith(color: AppColors.body, height: 17 / 12)),
          ),
        ),
      ),
    );
  }
}

/// `SGkJM` 12/400/1.4 #6A6A6A 가운데, pen 칸 높이 18.
class _Caption extends StatelessWidget {
  const _Caption();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: const ValueKey('paid-card-caption'),
      constraints: const BoxConstraints(minHeight: 18),
      child: Center(
        child: Text(
          '다음 카드가 오기 전까지 한 명만 열 수 있어요',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.muted),
        ),
      ),
    );
  }
}

/// `MHRC6` 물음표. pen 에는 보이는 크기 22 만 있고 눌림 칸 48 은 앱이 만든다(설계 문서 §8).
/// 눌림 효과는 이 칸의 Material 이 칠한다 — 화면 Material 에 칠하면 스크롤 때 공중에 뜬다(COMMON §4-2).
class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '맞는 이유 안내',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('paid-card-info'),
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Center(child: Icon3d(AppIcon3d.help, size: 22)),
        ),
      ),
    );
  }
}

/// 0명 상태 안내 상자 `IJGRA`(pen `SoMVZ` · 328×48). 후보는 있는데 지금 열 사람이 없을 때 결제 카드 자리에 들어간다.
/// 버튼도 눌림도 없다.
class PaidCardEmptyNotice extends StatelessWidget {
  const PaidCardEmptyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        // pen 모서리 12.
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Padding(
        // pen padding [14,16].
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.md),
        child: Row(
          children: [
            const Icon(AppIcons.lock, size: 14, color: AppColors.body),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '잘 맞는 새 사람이 들어오면 다시 열려요',
                // pen `DQPCm` 14/600, 칸 높이 20.
                style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 20 / 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
