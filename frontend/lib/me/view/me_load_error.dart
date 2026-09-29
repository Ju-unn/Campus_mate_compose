import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 나 탭 화면(15 · 15-4 · 15-5)의 읽기 실패. pen 에 없는 상태라 3c(`school_info_screen`)와 같은 모양(가운데 문구 +
/// "다시 시도")을 쓰고, 실패 사유와 상관없이 다시 해 보라는 안내 한 줄만 둔다(계획서 N9).
class MeLoadError extends StatelessWidget {
  const MeLoadError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  /// 사용자 결정 2026-09-27. 글자가 같은 `ServerUnavailableFailure` 는 뜻(502·503)이 달라 빌려 오지 않는다.
  static const _message = '잠시 뒤 다시 시도해 주세요';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_message, style: AppTypography.body.copyWith(color: AppColors.body)),
          AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
        ],
      ),
    );
  }
}
