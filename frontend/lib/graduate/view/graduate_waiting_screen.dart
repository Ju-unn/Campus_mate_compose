import 'dart:async';

import 'package:campus_mate/core/auth/logout_text_button.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 결과가 푸시로 오지 않았거나 놓쳤을 때를 위해 관문을 다시 묻는 간격(계획서 Task 7 `polls_gate_every_30s_and_on_resume`).
const Duration graduateWaitingPollInterval = Duration(seconds: 30);

/// 맨 아래 로그아웃 자리(높이 48 + 아래 16). 위에도 같은 만큼 비워 내용이 화면 가운데에 남게 한다.
const double _logoutSlot = 48 + AppSpacing.md;

/// pen `IENk4` 제목 `v9kQL` 18/700 — 줄높이 속성 없음 · 렌더 26(18c 와 같다).
final TextStyle _titleStyle = AppTypography.label.copyWith(color: AppColors.ink, height: 26 / 18);

/// pen 설명 `cgtMn` 14/500 muted — 줄높이 속성 없음 · 렌더 20(18c 와 같다).
final TextStyle _bodyStyle =
    AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500, color: AppColors.muted, height: 20 / 14);

/// 졸업생 확인 중(화면 02-g-2, pen `IENk4` — 18c `xA8en` 복사). 앱바 · 뒤로가기 · 단추가 없다.
/// 맨 아래에 로그아웃 글자 링크를 더했다(대장 결정 10-19, pen 에는 없음 — pen 수정 대기).
///
/// 닫는 동작은 시스템 뒤로이고 종료 안내다(이 화면이 맨 아래 한 장이라 [BackExitScope] 가 한 번 더 누르면 앱을 닫는다).
/// 승인 · 반려는 푸시가 알리지만 푸시만 믿지 않는다 — 30초마다, 그리고 앱이 다시 앞으로 올 때 관문을 직접 다시 묻는다
/// (푸시 갱신 · 앱 재개 갱신은 관문이 `complete` 일 때만 돈다). 값이 바뀌면 라우터가 화면을 옮긴다.
class GraduateWaitingScreen extends ConsumerStatefulWidget {
  const GraduateWaitingScreen({super.key});

  @override
  ConsumerState<GraduateWaitingScreen> createState() => _GraduateWaitingScreenState();
}

class _GraduateWaitingScreenState extends ConsumerState<GraduateWaitingScreen> with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(graduateWaitingPollInterval, (_) => _refreshGate());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshGate();
  }

  void _refreshGate() => unawaited(ref.read(verificationGateListenableProvider).refresh());

  @override
  Widget build(BuildContext context) {
    return BackExitScope(
      child: Scaffold(
        body: SafeArea(
          // 내용은 화면 가운데에 두고(위 64 = 아래 로그아웃 48 + 16 을 맞비워 pen 자리 그대로), 로그아웃은 맨 아래 16 에 둔다.
          child: Column(
            children: [
              const SizedBox(height: _logoutSlot),
              Expanded(
                child: Center(
                  // 글자를 키워 화면보다 길어지면 스크롤한다.
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    // pen `RdVKD` 폭 280, 세로 간격 16, 가운데 정렬.
                    child: SizedBox(
                      width: 280,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // pen `re3kH` 88×88(`mascot-female`). 옆 글자가 뜻을 말하는 장식이라 낭독기에서 뺀다.
                          Image.asset(
                            'assets/images/mascot-female.png',
                            width: 88,
                            height: 88,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text('졸업생 확인 중이에요', textAlign: TextAlign.center, style: _titleStyle),
                          const SizedBox(height: AppSpacing.md),
                          Text('결과는 알림으로 알려 드려요', textAlign: TextAlign.center, style: _bodyStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 02-0 과 같은 로그아웃(대장 결정 10-19) — 심사 중에 다른 계정으로 바꿀 길이다.
              const Padding(padding: EdgeInsets.only(bottom: AppSpacing.md), child: LogoutTextButton()),
            ],
          ),
        ),
      ),
    );
  }
}
