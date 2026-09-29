import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:campus_mate/referral/viewmodel/my_referral_code_provider.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16i 친구 초대 시트를 띄운다. 설정 "친구 초대" 줄이 부른다. 딤은 조각 6 시트와 같은 [showSafetySheet] 를 쓴다.
Future<void> showInviteFriendsSheet(BuildContext context) =>
    showSafetySheet<void>(context, (_) => const InviteFriendsSheet());

/// 16i(pen `eoJOg`, AlertSheet `D0TvG` 인스턴스 `vBZjk`). 내 추천 코드를 크게 보여 주고 복사 · 공유한다.
/// 위 모서리 24 · 그림자 #00000026 (0,-2) blur 16 · 손잡이 영역 위아래 12 · 내용 [8,16,32,16] 간격 16 —
/// 15d-2 삭제 확인(poll_sheets)과 같은 마스터다(공통 승격은 백로그 39). [SafetySheet] 는 여백이 달라 쓰지 않는다.
class InviteFriendsSheet extends ConsumerStatefulWidget {
  const InviteFriendsSheet({super.key});

  @override
  ConsumerState<InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends ConsumerState<InviteFriendsSheet> {
  // 50 은 redeem_referral 이 양쪽에 주는 하트(20260928010000_create_referrals.sql)와 같아야 한다.
  static const String _description = '친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.';

  /// 공유 창이 떠 있는 동안 다시 눌러도 두 번 열지 않는다.
  bool _sharing = false;

  /// 지금 떠 있는 안내. 19 대기 화면과 같은 방식 — 한 번에 하나, 3초. 체크 아이콘은 복사 안내(pen `CuNVR`)에만 단다.
  ({String label, IconData? icon})? _toast;
  Timer? _toastTimer;
  static const Duration _toastDuration = Duration(seconds: 3);

  void _showToast(String label, {IconData? icon}) {
    _toastTimer?.cancel();
    setState(() => _toast = (label: label, icon: icon));
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _showToast('코드를 복사했어요', icon: AppIcons.check);
  }

  Future<void> _share(String code) async {
    if (_sharing) return;
    _sharing = true;
    try {
      await ref.read(shareTextProvider)(inviteShareText(code));
    } catch (_) {
      // 공유 창을 못 열었다(기기 쪽 오류). 조용히 끝내지 않는다.
      if (mounted) _showToast(const UnknownFailure().toDisplayMessage());
    } finally {
      _sharing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    void retry() => ref.invalidate(myReferralCodeProvider);
    final myCode = ref.watch(myReferralCodeProvider);
    final code = myCode.value?.when<String?>(onSuccess: (code) => code, onFailure: (_) => null);
    final toast = _toast;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 토스트는 시트 윗변 16 위, 가로 가운데(pen `CuNVR` absolute y 353 = 시트 409 − 16 − 40).
        if (toast != null) ...[
          AppToast(
            label: toast.label,
            leading: toast.icon == null ? null : Icon(toast.icon, size: 16, color: AppColors.onInk),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Flexible(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              boxShadow: [BoxShadow(color: Color(0x26000000), offset: Offset(0, -2), blurRadius: 16)],
            ),
            child: SafeArea(
              top: false,
              // 글자를 키운 기기에서는 시트가 화면보다 길어진다 — 넘치는 만큼 스크롤한다.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Center(child: SheetHandle()),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // pen `xd8je` 20/700, 줄높이 속성 없음 · 렌더 29.
                          Text('친구 초대', style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20)),
                          const SizedBox(height: AppSpacing.md),
                          // pen `LEq3I` 14/400/1.55 #6A6A6A.
                          Text(_description, style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
                          const SizedBox(height: AppSpacing.md),
                          ...myCode.when(
                            loading: () => const [Center(child: CircularProgressIndicator())],
                            error: (_, _) => _loadError(const UnknownFailure().toDisplayMessage(), retry),
                            data: (result) => result.when(
                              onSuccess: (code) => [_CodeBox(code: code, onCopy: () => _copy(code))],
                              onFailure: (failure) => _loadError(failure.toDisplayMessage(), retry),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          // 버튼 묶음 `KMbP4` 간격 8. 코드가 없으면 보낼 것도 없다 — 공유하기를 뺀다.
                          if (code != null) ...[
                            AppButton(label: '공유하기', onPressed: () => _share(code)),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          AppButton(
                            label: '닫기',
                            variant: AppButtonVariant.text,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// pen 에 없는 상태(계획서 편차) — 16e `_LoadError` 와 같은 회색 문구 + 다시 시도.
  List<Widget> _loadError(String message, VoidCallback onRetry) => [
        Text(message, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.body)),
        AppButton(label: '다시 시도', variant: AppButtonVariant.text, onPressed: onRetry),
      ];
}

/// 코드 상자(pen `e3n2P`). surface-soft · 모서리 14 · 여백 [12,12,12,16] · 가로 간격 12.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          // pen `Kf6Wi` Type · display. 글자를 키워 자리가 모자라면 줄이 바뀌지 않게 코드만 줄여 보인다.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(code, style: AppTypography.display.copyWith(color: AppColors.ink)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _CopyButton(onPressed: onCopy),
        ],
      ),
    );
  }
}

/// 복사(pen `yAaQX`, Button 인스턴스). 44 · 모서리 12 · #E5E5E5 · 여백 [0,14] · 간격 6 · copy 16 · 14/600 —
/// AppButton(56 · 16 · 전체 폭)과 달라 여기 둔다. 모서리 12 는 같은 44 버튼 `vmfRQ` 값으로 토큰(8 · 14) 사이다.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // 눌림 효과가 시트와 같이 움직이게 버튼 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        color: AppColors.primaryDisabled,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          // 높이는 최소값만 건다 — 글자를 키우면 버튼이 따라 커진다.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.copy, size: 16, color: AppColors.ink),
                  const SizedBox(width: 6),
                  // pen `ifX9K` 14/600, 줄높이 속성 없음 · 렌더 20.
                  Text('복사', style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 20 / 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
