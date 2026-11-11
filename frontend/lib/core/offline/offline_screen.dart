import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/full_screen_notice.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 01-1 인터넷 없음(pen `NWGuf`, 결정 13 · B10). 앱을 켤 때 인증 관문을 못 물어봤으면 라우터가 여기로 보낸다.
/// "다시 시도" 로 관문을 알아내면 라우터가 원래 화면으로 옮긴다. 다시 실패하면 이 화면 그대로다(토스트 없음, 대장 10-03).
class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({super.key});

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  bool _isRetrying = false;

  /// 온보딩 단계를 먼저 다시 읽는다 — 앱을 켤 때 그것도 실패해 기본값(04-1)에 머물러 있어서,
  /// 관문이 먼저 바뀌면 라우터가 온보딩을 마친 사람을 04-1 로 보낸다(동의 화면 `ConsentViewModel.submit` 과 같은 순서).
  Future<void> _retry() async {
    setState(() => _isRetrying = true);
    final onboardingStep = ref.read(onboardingStepListenableProvider);
    final gate = ref.read(verificationGateListenableProvider);
    await onboardingStep.refresh();
    await gate.refresh();
    // 관문을 알아냈으면 라우터가 이 화면을 닫는다. 남아 있으면(다시 실패) 다시 누를 수 있게 한다.
    if (mounted) {
      setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // pen 프레임 padding [0,24,40,24], 위 여백 WqP2S 120 + 간격 20 → 안내, 요소 사이 간격 20.
        // 아래 여백 nzPoQ 184 는 남는 자리로 둔다 — 글자를 키운 기기에서는 안내만 스크롤하고 버튼은 바닥에 남는다.
        child: FullScreenNotice(
          notice: EmptyNotice(
            key: const ValueKey('offline-notice'),
            align: EmptyNoticeAlign.top,
            // 3D 안내 파란 느낌표 `s3b4k`.
            image: const Icon3d(AppIcon3d.infoBlue, size: 120),
            title: context.l10n.coreOfflineTitle,
            description: context.l10n.coreOfflineBody,
            // 큰 안내 제목 20/700 줄높이 1.5(렌더 30, pen `NWGuf`).
            titleStyle: EmptyNotice.largeTitleStyle,
          ),
          button: AppButton(label: context.l10n.commonRetry, isLoading: _isRetrying, onPressed: _retry),
        ),
      ),
    );
  }
}
