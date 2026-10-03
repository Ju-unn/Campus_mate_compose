import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:campus_mate/me/viewmodel/my_photos_view_model.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15-7 사진 수정(pen `szJ79`, 계획서 2026-09-27-me-edit.md 4절 15e 표 · A6). 15-5 "실제 사진 교체"(`E7Cv2`)가 연다.
/// 지금 사진이 채워진 칸에서 빼기 · 넣기 · 길게 눌러 순서를 바꾼 뒤 "저장" 한 번에 올리고 15-5 로 돌아간다(U2 · N8).
/// 칸은 2×2 [PhotoSlotGrid](2026-10-03 개편 — 옛 대표 160×200 + 보조 66×88), 칸 안은 04-2 칸 위젯 그대로(C9), 끌기 규칙도 같다.
class MyPhotosScreen extends ConsumerStatefulWidget {
  const MyPhotosScreen({super.key});

  @override
  ConsumerState<MyPhotosScreen> createState() => _MyPhotosScreenState();
}

class _MyPhotosScreenState extends ConsumerState<MyPhotosScreen> with MeToastHost<MyPhotosScreen> {
  /// 마지막 저장이 실패한 까닭. 사진 고르기 안내(얼굴 없음 · 최대 4장)와 같은 칸(`errorMessage`)으로 오지만 모양이 다르다 —
  /// 저장 실패는 버튼 위 오류 글(편집 화면 공통 규칙), 고르기 안내는 04-2 와 같은 토스트다. 다시 저장하면 지운다.
  String? _saveError;

  /// 그리드 열 간격 16 — 값표에 숫자가 없어 칸 폭 156 · 삭제 버튼 x120(오른쪽 8)에서 거꾸로 셈(대장 확인 2026-10-03).
  static const double _columnGap = 16;

  void _onStateChanged(PhotosUiState? previous, PhotosUiState next) {
    if (next.completed && !(previous?.completed ?? false)) {
      context.pop();
      return;
    }
    final saveEnded = (previous?.isSubmitting ?? false) && !next.isSubmitting;
    if (saveEnded || next.isSubmitting) {
      setState(() => _saveError = next.errorMessage);
      return;
    }
    final message = next.errorMessage;
    if (message != null) {
      showTimedToast(
        AppToast(leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk), label: message),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myPhotosViewModelProvider);
    final viewModel = ref.read(myPhotosViewModelProvider.notifier);
    ref.listen(myPhotosViewModelProvider, _onStateChanged);
    return Scaffold(
      appBar: const EditAppBar(title: '사진 수정'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              // 본문 `vAuNj` — 위 32 → 그리드 → 16 → 캡션. 그리드 `u6AR7K` 폭 328 이라 좌우 16.
              // 큰 글씨에서 캡션이 길어지면 스크롤로 내준다.
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xl, AppSpacing.md, 0),
                children: [
                  // 보내는 동안 칸을 바꾸면 성공 뒤 버려지고, 고르기 안내가 저장 오류 자리로 샌다 — 저장 중엔 막는다.
                  IgnorePointer(
                    ignoring: state.isSubmitting,
                    child: PhotoSlotGrid(state: state, viewModel: viewModel, columnGap: _columnGap),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '사진을 길게 눌러 끌면 순서를 바꿀 수 있어요. 첫 칸이 대표 사진이에요.',
                    // 14/400 muted — 줄높이 속성 없음 · 두 줄 렌더 40(C2).
                    style: AppTypography.bodySmall.copyWith(height: 20 / 14, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _Footer(
              toast: timedToast,
              error: _saveError,
              isSaving: state.isSubmitting,
              onSave: viewModel.canSave ? viewModel.save : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 고르기 안내 토스트(04-2 와 같은 모양, 버튼 위 12) → 저장 실패 글(caption · error, 버튼 위 8) → "저장"(`m2cAn` 312×56).
/// 버튼을 화면 아래에 붙이고 바 안쪽 [8,24,8,24](`A8INC6`, 2026-10-01 개편 — 옛 위 16 · 아래 28)를 두는 것은 15c 와 같다.
class _Footer extends StatelessWidget {
  const _Footer({required this.toast, required this.error, required this.isSaving, required this.onSave});

  final Widget? toast;
  final String? error;
  final bool isSaving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final toast = this.toast;
    final error = this.error;
    return Padding(
      padding: AppSpacing.bottomCta,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (toast != null) ...[
            Center(child: toast),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (error != null) ...[
            Text(error, style: AppTypography.caption.copyWith(color: AppColors.error)),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(label: '저장', onPressed: onSave, isLoading: isSaving),
        ],
      ),
    );
  }
}
