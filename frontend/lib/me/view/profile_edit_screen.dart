import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/me/viewmodel/profile_edit_view_model.dart';
import 'package:campus_mate/me/viewmodel/tag_edit_view_model.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 15c 자기소개 · 태그 수정(pen `zWMxM`, DESIGN §9 15c, 계획서 A4). 자기소개 입력 → 태그 섹션 셋(고른 칩만) → "저장".
/// "저장" 은 자기소개만 저장하고 15 로 돌아간다(U4). 태그는 섹션의 "수정 ›" 로 연 편집 화면이 따로 저장한다(T5).
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  /// 쓰던 자기소개는 컨트롤러가 들고 있다 — 태그 편집에서 돌아와 칩이 새로 그려져도 지워지지 않는다.
  late final TextEditingController _bio = TextEditingController(text: ref.read(profileEditViewModelProvider).bio);

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileEditViewModelProvider);
    final viewModel = ref.read(profileEditViewModelProvider.notifier);
    ref.listen(profileEditViewModelProvider, (previous, next) {
      if (next.completed && !(previous?.completed ?? false)) context.pop();
    });
    // 새로 읽는 동안에도 앞 값을 그대로 보여 준다(Riverpod 이 새로고침 중에 앞 값을 들고 있다).
    final profile = ref.watch(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    return Scaffold(
      appBar: const EditAppBar(title: '자기소개·태그 수정'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              // 본문 `jk11O` 좌우 24, 위 여백 `ol5br` 32.
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
                children: [
                  _BioField(controller: _bio, onChanged: viewModel.changeBio),
                  for (final (index, kind) in TagPickerKind.values.indexed)
                    _TagSection(
                      label: _sectionLabel(kind),
                      tags: profile?.tagsOf(kind) ?? const [],
                      // 입력 뒤 `cgqOw` 32, 섹션 사이 `a14aUL` gap 24.
                      topGap: index == 0 ? AppSpacing.xl : AppSpacing.lg,
                      onEdit: () => context.push('${AppRoutes.myTags}/${kind.endpoint}'),
                    ),
                ],
              ),
            ),
            _Footer(state: state, onSave: viewModel.save),
          ],
        ),
      ),
    );
  }

  /// 섹션 라벨(pen `LGk75` · `J1AY0X` · `GIPIe`). "관심사 태그" 는 pen 묶음 4 PNG · DESIGN §9 15c 와 같다(대장 09-28 —
  /// 계획서 표의 "관심사" 가 틀렸다).
  static String _sectionLabel(TagPickerKind kind) {
    return switch (kind) {
      TagPickerKind.interests => '관심사 태그',
      TagPickerKind.myTraits => '나의 특징',
      TagPickerKind.idealTraits => '이상형 특징',
    };
  }
}

/// 라벨 14/600 · 줄높이 속성 없음, 렌더 20(pen 섹션 헤더 · 입력 라벨) — 토큰 1.2 대신 20/14.
final _labelStyle = AppTypography.labelSmall.copyWith(height: 20 / 14);

/// 자기소개 입력 `YFZxt` — 라벨 8 아래 상자(높이 120 · 위 정렬 · 안쪽 [14,16]).
/// 모양은 앱의 입력 칸(`LabeledField`)과 같다(C1) — 상자 높이 · 안쪽 여백만 pen 값이라 여기서 그린다.
/// 120 은 최소값이다 — 글이 길거나 글자를 키우면 상자가 늘어난다(DESIGN §11.2).
class _BioField extends StatelessWidget {
  const _BioField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('자기소개', style: _labelStyle.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          // C1 — 값 글자는 #222222. placeholder 는 muted(2026-10-01 개편 — 옛 #929292).
          style: AppTypography.body.copyWith(color: AppColors.ink),
          decoration: InputDecoration(
            // 06-3 과 같은 안내 문구 — 서버 값이 늘 있어 지운 뒤에만 보인다.
            hintText: '나를 한두 문장으로 소개해주세요',
            hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
            filled: true,
            fillColor: AppColors.surfaceSoft,
            constraints: const BoxConstraints(minHeight: 120),
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
            // `TDM1r` 테두리 hairline 1. 포커스는 pen 에 상태가 없어 ink 2(대장 확인 2026-10-03).
            border: _border(AppColors.hairline),
            enabledBorder: _border(AppColors.hairline),
            focusedBorder: _border(AppColors.ink, width: 2),
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// 태그 섹션 `hTOUT` · `rns5Q` · `uRkpc` — 위 여백, 헤더 20(라벨 · "수정 ›" space_between), 8, 고른 칩만.
///
/// "수정 ›" 는 pen 에서 44×20 인데 누름 영역은 48 이다(C3). 헤더를 48 로 키우면 pen 간격이 어긋나므로, 48 칸을
/// 헤더 위에 겹쳐 세로 가운데를 맞춘다. 칸이 위로 삐져나가는 몫은 위 여백 안에 두어야 눌린다 — 상자 밖은 누름
/// 검사가 닿지 않는다. 그래서 위 여백을 섹션 상자 안([topGap])에 둔다.
class _TagSection extends StatelessWidget {
  const _TagSection({required this.label, required this.tags, required this.topGap, required this.onEdit});

  final String label;
  final List<String> tags;
  final double topGap;
  final VoidCallback onEdit;

  /// pen 이 정한 누름 영역(C3, DESIGN §10).
  static const double _tapTarget = 48;

  @override
  Widget build(BuildContext context) {
    // 헤더 한 줄 높이(배율 1.0 에서 20). 이 줄의 가운데에 48 칸을 맞춘다 — 글자를 키워도 "수정" 이 라벨과 나란하다.
    final lineHeight = MediaQuery.textScalerOf(context).scale(_labelStyle.fontSize!) * _labelStyle.height!;
    final linkHeight = lineHeight > _tapTarget ? lineHeight : _tapTarget;
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(top: topGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _labelStyle.copyWith(color: AppColors.body)),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [for (final tag in tags) _TagChip(label: tag)],
              ),
            ],
          ),
        ),
        Positioned(
          top: topGap + (lineHeight - linkHeight) / 2,
          right: 0,
          child: _EditLink(minHeight: linkHeight, onTap: onEdit),
        ),
      ],
    );
  }
}

/// "수정 ›" `cOkl1` — "수정" 14/600 primary-text, gap 2, chevron-right 16. 누름 칸은 최소 48×48, 글자는 칸 오른쪽 끝.
class _EditLink extends StatelessWidget {
  const _EditLink({required this.minHeight, required this.onTap});

  final double minHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 스크롤 안의 탭 위젯이라 눌림 효과를 그릴 Material 을 칸 크기로 둔다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: _TagSection._tapTarget, minHeight: minHeight),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            heightFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('수정', style: _labelStyle.copyWith(color: AppColors.primaryText)),
                // gap 2 는 pen 값(토큰 밖 리터럴).
                const SizedBox(width: 2),
                const Icon(AppIcons.chevronRight, size: 16, color: AppColors.primaryText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 칩 `WzXvK`(선택 꺼짐 모양) — surface-soft, 알약 모서리(2026-10-01 개편 — 옛 8), 안쪽 [8,12], 14/600 ink(렌더 20 → 칩 36). 누르지 않는다.
/// 폭은 글자만큼이다 — 줄 폭을 먹지 않아야 `Wrap` 이 한 줄에 여러 개를 놓는다.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('tag-chip'),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Text(label, style: _labelStyle.copyWith(color: AppColors.ink)),
      ),
    );
  }
}

/// 버튼 위 오류 글(온보딩 화면과 같은 caption · error) → "저장"(`zUZFx`). 바 안쪽은 `A8INC6` [8,24,8,24](2026-10-01 개편).
/// 버튼을 화면 아래에 붙이고 본문 끝과 16 을 두는 것은 06-3 과 같은 판단이다 — pen 값표에 버튼 자리 · 간격이 없다.
class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onSave});

  final ProfileEditUiState state;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final error = state.errorMessage;
    return Padding(
      padding: AppSpacing.bottomCta,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            Text(error, style: AppTypography.caption.copyWith(color: AppColors.error)),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(label: '저장', onPressed: state.canSave ? onSave : null, isLoading: state.isSubmitting),
        ],
      ),
    );
  }
}
