import 'package:campus_mate/auth/school_info/model/data/academic_status.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/profile/onboarding/view/profile_enum_text.dart';
import 'package:flutter/material.dart';

/// 신분 칩 한 줄(1.0.7 1-1) — 3c(pen `LIqAa`)와 15-6(`a6Wd1J`)이 같이 쓴다. 같은 폭 칩 3개 · 높이 33 · 사이 8,
/// 모양은 성별 · MBTI 와 같은 [SelectChip] 이다. [selected] 가 null 이면 모두 꺼져 있다("안 고름" 으로 되돌리는 칩은 없다).
///
/// 칸 폭은 최소값이다 — 글자를 키워(§11.2) "대학원생" 이 칸보다 넓어지면 칩이 글자만큼 늘고 다음 줄로 내려간다.
/// 칸을 고정하면 낱말 가운데서 줄이 바뀐다("대학원/생").
class AcademicStatusChips extends StatelessWidget {
  const AcademicStatusChips({required this.selected, required this.onSelect, super.key});

  final AcademicStatus? selected;
  final ValueChanged<AcademicStatus> onSelect;

  /// pen 실측 33 — SelectChip 기본(35)보다 2 낮다.
  static const double _height = 33;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => _chips(context, constraints.maxWidth));
  }

  Widget _chips(BuildContext context, double maxWidth) {
    // 내림 — 소수 오차로 셋째 칩이 다음 줄로 밀리지 않게.
    final width = ((maxWidth - AppSpacing.xs * 2) / 3).floorToDouble();
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [for (final status in AcademicStatus.values) _chip(context, status, width)],
    );
  }

  Widget _chip(BuildContext context, AcademicStatus status, double width) {
    return SelectChip(
      label: status.label(context.l10n),
      isSelected: status == selected,
      onTap: () => onSelect(status),
      width: width,
      height: _height,
    );
  }
}
