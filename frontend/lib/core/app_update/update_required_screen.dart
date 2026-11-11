import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/empty_notice.dart';
import 'package:campus_mate/common/widgets/full_screen_notice.dart';
import 'package:campus_mate/consent/model/repository/open_url.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/me/view/me_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 01-2 업데이트 필요(pen `zSzOG`, 01-1 인터넷 없음 `NWGuf` 와 같은 틀). 서버가 정한 최소 버전보다 낮은 앱을 막는다.
/// 뒤로가기 · 닫기가 없고, "업데이트하러 가기" 가 스토어 상세를 기기 앱으로 연다. 못 열면 짧은 토스트.
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  const UpdateRequiredScreen({required this.storeUrl, super.key});

  /// 구글 플레이 또는 앱 스토어 상세 주소(`UpdateRequired.storeUrl`).
  final String storeUrl;

  @override
  ConsumerState<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends ConsumerState<UpdateRequiredScreen>
    with WidgetsBindingObserver, MeToastHost<UpdateRequiredScreen> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 안드로이드 시스템 뒤로가기를 삼킨다. 이 화면은 라우터 바깥([UpdateGate], `MaterialApp.builder`)에 서서 내비게이터 경로가
  /// 아니라 아래 [PopScope] 가 아무것도 막지 못한다 — 안 삼키면 뒤로가기가 앱을 닫는다. 화면이 사라지면 옵저버도 빠진다.
  @override
  Future<bool> didPopRoute() async => true;

  /// 기기 앱으로 스토어를 연다. 주소가 비었거나 열지 못하면(false · 예외) 조용히 끝내지 않고 안내를 띄운다.
  Future<void> _openStore() async {
    if (_opening) return; // 여는 호출이 끝나기 전에 다시 눌러도 두 번 열지 않는다
    _opening = true;
    var opened = false;
    try {
      final uri = Uri.tryParse(widget.storeUrl);
      if (uri != null && uri.hasScheme) {
        opened = await ref.read(openExternalUrlProvider)(uri);
      }
    } catch (_) {
      // 기기 쪽 오류 — 아래에서 안내한다.
    } finally {
      _opening = false;
    }
    if (!opened && mounted) {
      // 스토어를 못 열었을 때 안내 문구는 사용자 승인 문구다(문구 파일 `errorStoreOpenFailed`).
      showTimedToast(
        AppToast(
          leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
          label: context.appErrorText(AppError.storeOpenFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          // pen 프레임 padding [0,24,40,24], 위 여백 A8PzaL 120 + 간격 20 → 안내, 요소 사이 간격 20. 아래 여백 vm26d 는 남는 자리로 둔다 —
          // 글자를 키운 기기에서는 안내만 스크롤하고 버튼은 바닥에 남는다. 토스트는 안내 칸의 맨 아래(= 버튼 위)에 뜬다.
          child: FullScreenNotice(
            regionBuilder: (region) => MeToastLayer(toast: timedToast, child: region),
            notice: EmptyNotice(
              key: const ValueKey('update-notice'),
              align: EmptyNoticeAlign.top,
              // 안쪽 여백 **[48,0]**(기본 [48,24] 에서 가로만 바꿨다 — 설명을 312 폭 두 줄로).
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              // 마스코트 `g1EMq7` = Mascot Male · Blue Scarf · Waiting `PKbwO` 120×120.
              image: Image.asset(
                'assets/images/mascot-male-waiting.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              title: context.l10n.coreUpdateTitle,
              // 큰 안내 제목 20/700 줄높이 1.5(렌더 30, pen `zSzOG`).
              titleStyle: EmptyNotice.largeTitleStyle,
              description: context.l10n.coreUpdateBody,
            ),
            button: AppButton(label: context.l10n.coreUpdateButton, onPressed: _openStore),
          ),
        ),
      ),
    );
  }
}
