import 'package:campus_mate/account/viewmodel/kakao_id_settings_ui_state.dart';
import 'package:campus_mate/account/viewmodel/kakao_id_settings_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/notice_card.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 16e-1 카카오톡 아이디 변경(pen `bWrnD`). 16e 계정의 카카오톡 줄과 14f 신뢰 확인 시트의 "변경"이 연다.
/// 저장하면 true 를 들고 닫힌다 — 연 쪽이 그걸 보고 다시 읽는다.
class KakaoIdSettingsScreen extends ConsumerStatefulWidget {
  const KakaoIdSettingsScreen({super.key});

  @override
  ConsumerState<KakaoIdSettingsScreen> createState() => _KakaoIdSettingsScreenState();
}

class _KakaoIdSettingsScreenState extends ConsumerState<KakaoIdSettingsScreen> {
  /// 저장된 아이디는 화면이 뜬 뒤에 도착한다 — `initialValue` 로는 늦어서 컨트롤러로 채운다.
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStateChanged(KakaoIdSettingsUiState? previous, KakaoIdSettingsUiState next) {
    if (previous?.isLoading == true && !next.isLoading) {
      _controller.text = next.kakaoIdInput;
    }
    if (next.completed && previous?.completed != true) {
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kakaoIdSettingsViewModelProvider);
    final viewModel = ref.read(kakaoIdSettingsViewModelProvider.notifier);
    ref.listen(kakaoIdSettingsViewModelProvider, _onStateChanged);
    return Scaffold(
      appBar: AppBar(title: Text('카카오톡 아이디', style: AppTypography.navTitle)),
      body: SafeArea(
        top: false,
        child: Padding(
          // 04-1b 와 같은 틀 — 좌우 24, 아래 28, 저장 버튼 하단 고정(pen u6wJjx (24,640) 312×56).
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      // pen `pEaoR` 16/normal/#3F3F3F/1.6.
                      Text('신뢰 확인을 마친 상대에게만 공개돼요.', style: AppTypography.body.copyWith(color: AppColors.body)),
                      const SizedBox(height: AppSpacing.xl),
                      // pen `HGpMk` — helper 없음(04-1b 의 "설정 > 계정에서…"는 여기서 할 말이 아니다).
                      LabeledField(
                        label: '카카오톡 아이디',
                        controller: _controller,
                        onChanged: viewModel.change,
                        errorText: state.errorMessage,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // pen `VBABp` = 04-1b `W2tFQt` 와 글자 · 스타일 1:1 — 같은 위젯을 그대로 쓴다(복사 금지).
                      const NoticeCard(
                        isEmphasis: true,
                        title: '꼭 확인해 주세요',
                        body: '카카오톡에서 \'ID 검색 허용\'을 켜주셔야 상대가 내 아이디를 검색할 수 있어요. '
                            '꺼져 있으면 신뢰 확인을 마쳐도 연락이 닿지 않아요.',
                        footer: '카카오톡 > 설정 > 프로필 관리 > 카카오톡 ID 에서 켤 수 있어요',
                        child: KakaoSettingExample(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '저장', onPressed: state.canSubmit ? viewModel.save : null),
            ],
          ),
        ),
      ),
    );
  }
}
