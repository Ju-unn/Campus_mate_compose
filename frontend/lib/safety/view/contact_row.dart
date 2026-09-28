import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 연락처 한 줄(pen ContactRow 마스터 `s3a2m`) — 8d 선택(체크 칸)과 16b 관리(휴지통)가 같이 쓴다.
/// 312×60, 간격 12, 채움 없음, 아래 선 hairline-soft 1(마스터 stroke 가 구분선 역할).
class ContactRow extends StatelessWidget {
  const ContactRow({
    required this.name,
    required this.number,
    this.selected,
    this.onTap,
    this.onRemove,
    this.showInitial = true,
    super.key,
  });

  final String name;
  final String number;

  /// null 이면 체크 칸이 없다(16b — pen `CheckOn` · `CheckOff` 둘 다 꺼짐).
  final bool? selected;

  /// 줄 전체를 누르는 동작(8d 선택 토글). null 이면 줄은 누를 수 없다.
  final VoidCallback? onTap;

  /// null 이면 휴지통이 없다(8d — pen `w7vUs0` 꺼짐).
  final VoidCallback? onRemove;

  /// 아바타에 이름 첫 글자를 쓸지. 이름을 모르는 줄(pen `J2OCDM`)은 빈 원이다.
  final bool showInitial;

  @override
  Widget build(BuildContext context) {
    // 눌림 효과는 줄 크기의 투명 Material 에 그린다 — 목록과 같이 움직인다(COMMON §4-2).
    return Semantics(
      checked: selected,
      child: Material(
        type: MaterialType.transparency,
        // 16b 줄은 누르지 않는다 — 잉크를 그릴 InkWell 도 두지 않는다(누르는 것은 휴지통뿐).
        child: onTap == null ? _content() : InkWell(onTap: onTap, child: _content()),
      ),
    );
  }

  Widget _content() {
    return Container(
      // 높이는 최소값만 — 글자를 키우면 줄이 따라 커진다.
      constraints: const BoxConstraints(minHeight: 60),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hairlineSoft))),
      child: Row(
        children: [
          _Avatar(initial: showInitial && name.isNotEmpty ? name.characters.first : null),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _NameColumn(name: name, number: number)),
          if (selected != null) ...[const SizedBox(width: AppSpacing.sm), _CheckBox(checked: selected!)],
          if (onRemove != null) ...[const SizedBox(width: AppSpacing.sm), _RemoveButton(onPressed: onRemove!)],
        ],
      ),
    );
  }
}

/// 아바타(pen `s4Udw` → Avatar `eNFmA`): 36 원, 인스턴스가 채움을 surface-strong 로 덮었다. 이니셜 17/600 ink.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  final String? initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceStrong),
      // 글자를 키워도 원은 36 그대로다 — 한 글자라 넘치면 원 밖으로 조금 나갈 뿐 잘리지 않게 줄이지 않는다.
      child: initial == null
          ? null
          : Text(initial!, maxLines: 1, style: AppTypography.subtitle.copyWith(color: AppColors.ink, height: 1)),
    );
  }
}

/// 이름칸(pen `r7RJcM`, 간격 2): 이름 `U2qgG6` 16/600 ink · 번호 `vNOl5` 14/400 muted.
class _NameColumn extends StatelessWidget {
  const _NameColumn({required this.name, required this.number});

  final String name;
  final String number;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 글자를 키워 줄이 60 보다 커질 때 위아래가 선에 붙지 않게 한다.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Column(
        // 줄 높이는 글자가 정한다 — 기본값(max)이면 부모가 주는 높이만큼 늘어난다.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 1.4)),
          const SizedBox(height: 2),
          _Number(number: number),
        ],
      ),
    );
  }
}

/// 번호칸. `010-****-2841` 은 줄바꿈 자리가 없는 한 덩어리라(폭 없는 공백 U+200B 도 테스트 글꼴에서 접히지 않았다)
/// 글자를 키우면 끝자리가 잘린다 — 하이픈 뒤마다 조각을 나눠 Wrap 으로 접는다. 보이는 글자와 크기는 그대로고,
/// 읽어 주기는 번호 한 줄로 묶는다.
class _Number extends StatelessWidget {
  const _Number({required this.number});

  final String number;

  /// "010-" · "****-" · "2841" 처럼 하이픈을 앞 조각에 붙여 자른다. 하이픈이 없으면 통째로 한 조각이다.
  static final RegExp _segment = RegExp(r'[^-]*-|[^-]+');

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.4);
    return Semantics(
      label: number,
      excludeSemantics: true,
      child: Wrap(children: [for (final match in _segment.allMatches(number)) Text(match[0]!, style: style)]),
    );
  }
}

/// 체크 칸 24, 모서리 6. 켜짐(pen `ORl5o`) primary 채움 + 흰 체크 16, 꺼짐(`zlg4q`) 흰 채움 + outline 테두리.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  /// pen 모서리 6 은 라운드 토큰(sm 8)보다 작은 값이다.
  static const double _radius = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      // 가운데 정렬이 없으면 Container 가 체크 아이콘을 24 로 조인다(pen 체크 16).
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? AppColors.primary : AppColors.canvas,
        borderRadius: BorderRadius.circular(_radius),
        border: checked ? null : Border.all(color: AppColors.outline),
      ),
      child: checked ? const Icon(AppIcons.check, size: 16, color: AppColors.onPrimary) : null,
    );
  }
}

/// 휴지통(pen `w7vUs0` 20, disabled 색). pen 에 누르는 영역이 따로 없어 48×48 로 넓힌다(지시서).
/// 아이콘은 오른쪽 끝에 붙여 pen 자리 그대로 둔다 — 넓힌 영역은 이름칸 쪽으로 자란다.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      // 읽어 주기용 이름. pen 에 없는 글자라 화면에는 보이지 않게 semanticLabel 로만 단다.
      icon: const Icon(AppIcons.trash2, size: 20, color: AppColors.disabled, semanticLabel: '차단 해제'),
      alignment: Alignment.centerRight,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    );
  }
}
