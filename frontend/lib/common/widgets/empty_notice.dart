import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 빈 화면 안내를 놓는 방식.
enum EmptyNoticeAlign {
  /// 칸 한가운데(글자를 키워 넘치면 스크롤한다). 목록 · 피드의 빈 상태.
  center,

  /// 위에서부터 안쪽 여백만큼 띄워 놓는다. 스크롤과 위쪽 띄움은 쓰는 쪽이 정한다(알림 · 큰 안내 화면).
  top,
}

/// 빈 화면 안내(pen Empty `TVc8b`): 그림 120×120 → 24 → 제목 18/600 ink(렌더 25) → 8 → 설명 14 muted 1.55 → (선택 버튼, 앞 간격 32),
/// 안쪽 [세로 48, 가로 24], 가운데 정렬. 문구는 쓰는 화면이 `context.l10n` 으로 만들어 넘긴다.
class EmptyNotice extends StatelessWidget {
  const EmptyNotice({
    required this.image,
    required this.title,
    this.description,
    this.descriptionWidget,
    this.action,
    this.actionGap = AppSpacing.xl,
    this.align = EmptyNoticeAlign.center,
    this.padding = defaultPadding,
    this.scrollPadding = EdgeInsets.zero,
    this.titleStyle,
    super.key,
  });

  /// 안내 안쪽 여백 `TVc8b` [세로 48, 가로 24].
  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(vertical: AppSpacing.xxl, horizontal: AppSpacing.lg);

  /// 큰 안내 화면(알림 불러오기 실패 vGd3l · 인터넷 없음 NWGuf · 업데이트 zSzOG)의 제목 — navTitle 20/700 ink, 줄높이 1.5(렌더 30).
  static final TextStyle largeTitleStyle = AppTypography.navTitle.copyWith(color: AppColors.ink);

  /// 그림. 120×120 상자 안에 놓는다(마스코트 · 3D 아이콘).
  final Widget image;
  final String title;

  /// 설명 글자. 없으면(그리고 [descriptionWidget] 도 없으면) 제목까지만 그린다.
  final String? description;

  /// 설명 자리에 글자 대신 위젯을 놓는다(여러 줄 + 링크). [description] 보다 먼저 쓴다.
  final Widget? descriptionWidget;

  /// 설명 아래 버튼. [actionGap] 만큼 띄운다.
  final Widget? action;
  final double actionGap;
  final EmptyNoticeAlign align;

  /// 안내 안쪽 여백. 기본은 `TVc8b` [48,24].
  final EdgeInsets padding;

  /// [EmptyNoticeAlign.center] 에서 스크롤 칸 바깥 여백(목록 여백 안에 놓이는 차단 목록). 안쪽 칸의 가운데에 놓인다.
  final EdgeInsets scrollPadding;

  /// 기본 제목은 18/600 ink 25/18. 큰 안내 화면 3곳(알림 실패 · 인터넷 없음 · 업데이트)만 [largeTitleStyle] 을 넘긴다.
  final TextStyle? titleStyle;

  static final TextStyle _defaultTitleStyle = AppTypography.subtitle.copyWith(color: AppColors.ink, height: 25 / 18);
  static final TextStyle _descriptionStyle = AppTypography.bodySmall.copyWith(color: AppColors.muted);

  @override
  Widget build(BuildContext context) {
    final content = _content();
    return switch (align) {
      EmptyNoticeAlign.top => Padding(padding: padding, child: SizedBox(width: double.infinity, child: content)),
      EmptyNoticeAlign.center => _centered(content),
    };
  }

  Widget _centered(Widget content) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: scrollPadding,
        child: ConstrainedBox(
          // 칸 높이만큼 채워 가운데에 둔다. 글자를 키워 넘치면 스크롤한다. 높이가 정해지지 않은 자리(머리 아래 목록 칸)에서는 내용만큼만 선다.
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight - scrollPadding.vertical : 0,
          ),
          child: Center(child: Padding(padding: padding, child: content)),
        ),
      ),
    );
  }

  Widget _content() {
    final detail = descriptionWidget ?? _descriptionText();
    final button = action;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: 120, child: image),
        const SizedBox(height: AppSpacing.lg),
        Text(title, textAlign: TextAlign.center, style: titleStyle ?? _defaultTitleStyle),
        if (detail != null) ...[const SizedBox(height: AppSpacing.xs), detail],
        if (button != null) ...[SizedBox(height: actionGap), button],
      ],
    );
  }

  Widget? _descriptionText() {
    final text = description;
    if (text == null) return null;
    return Text(text, textAlign: TextAlign.center, style: _descriptionStyle);
  }
}
