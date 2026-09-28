import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

const String _title = '확인하고 있어요';
const String _body = '확인이 끝나면 무료로 하트 모으기 목록에서 결과를 볼 수 있어요';
const String _duration = '보통 영업일 1~2일 걸려요';

/// pen 14/500 #6A6A6A, 줄높이 속성 없음 · 렌더 20.
final TextStyle _bodyStyle =
    AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted, height: 20 / 14);

/// 18c 검수 대기(pen `xA8en`). 앱바 · 버튼이 없다 — 18b 가 이 화면으로 바뀌었으므로 시스템 뒤로가 18a 로 간다.
/// 결과 푸시는 없다(계획서 D2) — 18a 상태와 잔액으로 확인한다.
class HeartTaskPendingScreen extends StatelessWidget {
  const HeartTaskPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            // pen `Bjhpo` 폭 280, 세로 간격 16.
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // DESIGN 은 128 이지만 pen 88 을 따른다(대장 09-28, DESIGN 은 문서 정리 때).
                  Image.asset('assets/images/mascot-female.png', width: 88, height: 88, fit: BoxFit.contain),
                  const SizedBox(height: AppSpacing.md),
                  // pen `AI5GP` 18/700, 렌더 26(label 토큰 줄높이 1.2 면 22 라 묶음이 pen 보다 4 짧다).
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(color: AppColors.ink, height: 26 / 18),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(_body, textAlign: TextAlign.center, style: _bodyStyle),
                  const SizedBox(height: AppSpacing.md),
                  Text(_duration, textAlign: TextAlign.center, style: _bodyStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
