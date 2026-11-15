import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_dialog_route.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 팝업 카드 상자. 시험이 pen 크기를 재는 데 쓴다.
const Key confirmPopupCardKey = ValueKey('confirm-popup-card');

/// 공용 확인 팝업을 띄운다(pen "Row X · 확인 팝업" — 일반 `v14xI` · 위험 `xCdlQ` · 설명 없음 `BDVsY`, 대장 전달 값표 2026-11-16).
/// 확인하면 true, 취소 · 바깥 탭 · 뒤로가기는 false. 앱의 "~할까요?" 확인은 모두 이것을 쓴다 — 무엇을 고르는 시트
/// (하트 구매 · 신고 사유 · 아바타 다시 만들기 · 탈퇴 1차 · 하트 부족)는 시트로 둔다.
///
/// [danger] 면 확인이 빨강 채움(되돌릴 수 없는 일). [body] 가 없으면 제목만 그린다(로그아웃).
/// [confirmLeading] 은 확인 라벨 앞 그림(유료 카드 하트 22).
/// [onConfirm] 을 주면 확인을 누른 뒤 그 일이 끝날 때까지 팝업 안에서 기다린다 — 확인은 색 그대로 흰 도는 표시로 바뀌어
/// 다시 눌리지 않고(사용자 「빨간 버튼 + 돌아가는 표시」), 취소 · 바깥 탭은 그대로 닫는다(일은 계속 끝난다). 끝나면 닫고 true.
/// 실패 알림은 부른 쪽이 [onConfirm] 안에서 정한다.
Future<bool> showConfirmPopup(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? body,
  bool danger = false,
  Widget? confirmLeading,
  Future<void> Function()? onConfirm,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (_) => _ConfirmPopup(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      danger: danger,
      confirmLeading: confirmLeading,
      onConfirm: onConfirm,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmPopup extends StatefulWidget {
  const _ConfirmPopup({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.danger,
    required this.confirmLeading,
    required this.onConfirm,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final bool danger;
  final Widget? confirmLeading;
  final Future<void> Function()? onConfirm;

  @override
  State<_ConfirmPopup> createState() => _ConfirmPopupState();
}

class _ConfirmPopupState extends State<_ConfirmPopup> {
  bool _busy = false;

  Future<void> _confirm() async {
    final work = widget.onConfirm;
    if (work == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = true);
    await work();
    // 취소 · 바깥 탭으로 이미 닫히는 중이면(애니메이션 동안 State 는 살아 있다) 또 닫지 않는다 — 밑 화면이 닫힌다.
    if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmPopupCard(
      title: widget.title,
      body: widget.body,
      confirmLabel: widget.confirmLabel,
      danger: widget.danger,
      confirmLeading: widget.confirmLeading,
      isLoading: _busy,
      onConfirm: _confirm,
      onCancel: () => Navigator.of(context).pop(false),
    );
  }
}

/// 확인 팝업 카드 — 화면 가운데에 두고, 좁은 화면에서는 좌우 20 을 두고 줄어들며, 글자를 키워 길어지면 스크롤한다.
/// 카드 320 · 흰 바탕 · 모서리 24 · 팝업 그림자 · 안쪽 위 24 · 좌우 20 · 아래 20. 제목 → 12 → 설명 → 20 → 버튼 줄
/// (같은 폭 · 사이 8 · 왼쪽 취소 · 오른쪽 확인). 제목 · 설명은 가운데 정렬(사용자 결정 2026-11-16 「설명도 가운데」).
/// [showConfirmPopup] 이 쓰고, 상태를 뷰모델이 쥔 팝업(탈퇴 최종)은 이것을 직접 그린다 — [error] 는 그때만 쓰는 실패 한 줄(pen 에 없는 상태).
class ConfirmPopupCard extends StatelessWidget {
  const ConfirmPopupCard({
    required this.title,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.body,
    this.danger = false,
    this.confirmLeading,
    this.isLoading = false,
    this.error,
    super.key,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final bool danger;
  final Widget? confirmLeading;

  /// 처리 중 — 확인은 색 그대로 흰 도는 표시, 다시 눌리지 않는다.
  final bool isLoading;
  final String? error;
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;

  /// pen 실측 20 = 카드 안쪽 토큰(카드 좌우 · 아래 안쪽 여백, 좁은 화면의 바깥 여백, 제목·설명 → 버튼 줄).
  static const double _edge = AppSpacing.card;

  /// pen 카드 폭.
  static const double _width = 320;

  /// 확인 앞 그림 자리(유료 카드 하트 22 + 간격 8). 라벨이 반쪽에 들어가는지 잴 때만 쓴다.
  static const double _leadingRoom = 30;

  /// 왼쪽 취소 · 오른쪽 확인(같은 폭 · 사이 8). 글자를 키워 반쪽 버튼(높이 52 고정)에 라벨이 한 줄로 안 들어가면
  /// 잘리지 않게 확인 위 · 취소 아래로 쌓는다 — pen 에 큰 글자 상태가 없어 정한 모양이다(DESIGN §11.2).
  Widget _buttons(BuildContext context, double width) {
    final cancelLabel = context.l10n.commonCancel;
    final cancel = AppButton(label: cancelLabel, variant: AppButtonVariant.tonal, onPressed: onCancel);
    final confirm = AppButton(
      label: confirmLabel,
      variant: danger ? AppButtonVariant.dangerStrong : AppButtonVariant.primary,
      leading: confirmLeading,
      isLoading: isLoading,
      onPressed: onConfirm,
    );
    final half = (width - AppSpacing.xs) / 2;
    final fits = _oneLineWidth(context, cancelLabel) <= half &&
        _oneLineWidth(context, confirmLabel) + (confirmLeading == null ? 0 : _leadingRoom) <= half;
    if (fits) {
      return Row(
        children: [Expanded(child: cancel), const SizedBox(width: AppSpacing.xs), Expanded(child: confirm)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [confirm, const SizedBox(height: AppSpacing.xs), cancel],
    );
  }

  /// 버튼 라벨(16/700)을 지금 글자 배율로 한 줄에 그렸을 때의 폭.
  static double _oneLineWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: AppTypography.button),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    final error = this.error;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: _edge),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _width),
          // 낭독기에는 창 하나로, 이름은 제목으로 알린다 — 팝업이 열리면 제목이 먼저 읽힌다(검토 2026-11-16).
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: Container(
              key: confirmPopupCardKey,
              padding: const EdgeInsets.fromLTRB(_edge, AppSpacing.lg, _edge, _edge),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppElevation.popup,
              ),
              // 글자 기본 모양을 주는 용도다(팝업 경로에는 Material 이 없다).
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // pen 20/700 ink · 줄높이 1.5 · 자간 -0.4 = navTitle 토큰 그대로.
                    Text(title, textAlign: TextAlign.center, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
                    if (body != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(error, textAlign: TextAlign.center, style: AppTypography.caption.copyWith(color: AppColors.error)),
                    ],
                    // 세로 간격 12 + 버튼 줄 위 여백 8. 설명 없음 변형도 제목 → 버튼 20 이다.
                    const SizedBox(height: _edge),
                    LayoutBuilder(builder: (context, constraints) => _buttons(context, constraints.maxWidth)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
