import 'dart:math' as math;

import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 읽기만 하는 태그(pen Z54et `Tag` `nAfU0` — 높이 28 · 알약 · 좌우 11).
/// 고르는 칩 `SelectChip`(높이 35)과 다르다.
/// [label] 은 참여 대학 이름(`universities.name`)이라 학교 줄(`SchoolLabel`)과 같은 로고 표([universityLogosProvider])에서
/// 로고를 찾는다. 로고가 있으면 pen 참여 대학 칩(`zOaUW` 의 `T2Pfi4` 등)처럼 좌우 6 · 로고 14×14 · 사이 4 · 글자다(School Symbol
/// `VI8eN` 등). 로고가 없는 학교 · 로고 표를 아직 읽는 중 · 그림을 못 불러오면 글자만, 좌우는 마스터 그대로 11 이다.
/// 그림이 오는 동안은 로고 칸 14 를 비워 둔다 — 도착해도 칩 폭이 그대로다(`SchoolLabel` 과 같은 방식).
/// [mine] 은 참여 대학 줄의 내 학교(pen `zOaUW` 의 `T2Pfi4`) — primary-wash 채움 · primary-text 글자.
/// 색만으로 가르지 않도록 스크린리더에는 "내 학교" 를 같이 읽힌다(pen `zOaUW` context). 로고는 읽히지 않는다.
class Tag extends ConsumerWidget {
  const Tag({required this.label, this.mine = false, super.key});

  final String label;
  final bool mine;

  /// pen 로고(`k6HUy3` 등) 14×14 — 글자 12 보다 2 크다(`SchoolLabel` 규칙과 같다).
  static const double _logo = 14;

  /// 로고가 있을 때 칩 좌우(pen `T2Pfi4` padding [0,6]) · 글자만일 때 좌우(마스터 `nAfU0` padding [0,11]). 토큰 밖 pen 값.
  static const double _logoPadding = 6;
  static const double _textPadding = 11;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // pen 글자 `aVMeb` 12 · lineHeight 1.5(줄 18) — caption 토큰은 1.40 이라 맞춘다.
    final style = AppTypography.caption.copyWith(height: 1.5, color: mine ? AppColors.primaryText : AppColors.body);
    final text = Text(label, style: style);
    final textOnly = Padding(padding: const EdgeInsets.symmetric(horizontal: _textPadding), child: text);
    final url = ref.watch(universityLogosProvider).value?[label];
    final content = url == null
        ? textOnly
        : Image.network(
            url,
            width: _logo,
            height: _logo,
            excludeFromSemantics: true,
            // 칩 안을 통째로 그림 빌더가 그린다 — 못 불러오면 errorBuilder 가 로고 몫 좌우 6 까지 글자만의 11 로 되돌린다
            // (errorBuilder 는 frameBuilder 를 거치지 않는다).
            frameBuilder: (context, logo, frame, wasSynchronouslyLoaded) => _withLogo(context, logo, text),
            errorBuilder: (context, error, stackTrace) => textOnly,
          );
    // pen 높이 28 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    final tag = Container(
      constraints: const BoxConstraints(minHeight: 28),
      decoration: BoxDecoration(
        color: mine ? AppColors.primaryWash : AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // `alignment` 을 쓰면 Wrap 안에서 폭을 다 먹는다 — 글자 폭만큼만 차지하게 한다.
      child: Center(widthFactor: 1, child: content),
    );
    return mine ? Semantics(label: '내 학교', child: tag) : tag;
  }

  /// 로고는 글자 첫 줄 가운데 — 글자를 키워도 14 그대로다. 이름이 두 줄로 접혀도 첫 줄 옆에 남는다(`SchoolLabel` 과 같은 규칙).
  Widget _withLogo(BuildContext context, Widget logo, Text text) {
    final firstLine = MediaQuery.textScalerOf(context).scale(text.style!.fontSize!) * text.style!.height!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _logoPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: math.max(0, (firstLine - _logo) / 2), right: AppSpacing.xxs),
            child: logo,
          ),
          Flexible(child: text),
        ],
      ),
    );
  }
}
