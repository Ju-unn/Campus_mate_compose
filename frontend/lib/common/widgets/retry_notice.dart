import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 불러오기 실패 안내(작은 것): 문구 16 muted 가운데 → 12 → "다시 시도" 글자 버튼(48, 전체 폭).
/// pen 에 없는 상태라 16f 차단 목록의 회색 문구 + 글자 버튼을 기준으로 삼았다. 문구는 쓰는 화면이
/// `context.errorText(...)` / `context.appErrorText(...)` 로 만들어 넘긴다(공통 위젯이 에러 키를 읽지 않는다).
///
/// 기본은 화면용(가운데, 글자를 키워 넘치면 스크롤, 사방 24). 구역 · 시트 안에 끼워 넣을 때는 [RetryNotice.inline].
class RetryNotice extends StatelessWidget {
  const RetryNotice({required this.message, required this.onRetry, super.key}) : _inline = false;

  /// 감싸기(가운데 · 스크롤 · 여백) 없이 문구 + 버튼 조각만 — 하트 스토어 구역 · 친구 초대 시트 안.
  const RetryNotice.inline({required this.message, required this.onRetry, super.key}) : _inline = true;

  final String message;

  /// "다시 시도" 를 눌렀을 때. `Future` 를 돌려주는 함수도 그대로 넘길 수 있다.
  final VoidCallback onRetry;
  final bool _inline;

  @override
  Widget build(BuildContext context) {
    final piece = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.muted)),
        const SizedBox(height: AppSpacing.sm),
        AppButton(label: context.l10n.commonRetry, variant: AppButtonVariant.text, onPressed: onRetry),
      ],
    );
    if (_inline) return piece;
    return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpacing.lg), child: piece));
  }
}
