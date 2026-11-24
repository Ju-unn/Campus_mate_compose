import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/view/category_chip.dart';
import 'package:campus_mate/community/view/poll_feed_tabs.dart';
import 'package:campus_mate/community/view/vote_option.dart';
import 'package:campus_mate/community/viewmodel/community_composer_view_model.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 글자 수는 서버(`len`) · DB(`char_length`)와 같은 **유니코드 코드 포인트** 로 센다.
/// Flutter `maxLength` 는 글자 모양(그래핌) 단위라 이모지(👍🏻 = 2)가 섞이면 앱은 통과시키고 서버가 422 를 낸다.
TextInputFormatter _maxCodePoints(int max) => TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.runes.length <= max) return newValue;
      final text = String.fromCharCodes(newValue.text.runes.take(max));
      return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    });

/// pen 덩어리 사이 20(토큰 밖).
const double _sectionGap = 20;

/// 입력칸 높이: 투표 질문 100(`YuHSq`, 대장 10-08) · 게시물 본문 220(`EcZyq`).
const double _pollBoxHeight = 100;
const double _postBoxHeight = 220;

/// 17b 글쓰기 — 투표(pen `YuHSq` 질문 작성, 옛 17b `tKjGJ` · `Xe28J`)와 게시물(pen `EcZyq` 처음 · `Efyv9` 쓰는 중).
/// 종류는 피드의 고르기 시트(17 `LSCrq`)가 정해 주소 `?kind=` 로 넘긴다(없으면 투표). 상태 · 보내기는
/// [CommunityComposerViewModel] 이 맡고, 화면은 입력칸 글자(컨트롤러)만 들고 있다.
/// 위 → 아래: 안내 상자 → 20 → 카테고리(필수, 칩 셋) → 20 → 본문 → 20 → (투표면 투표 방식 → 20) → 올리기.
class PollComposerScreen extends ConsumerStatefulWidget {
  const PollComposerScreen({this.kind, super.key});

  /// 넘기지 않으면 주소의 `?kind=` 를 읽는다(라우터는 화면만 만든다).
  final CommunityKind? kind;

  /// 고르기 시트에서 고른 종류의 글쓰기 주소.
  static String location(CommunityKind kind) => '${AppRoutes.communityNew}?kind=${kind.name}';

  static const questionKey = Key('poll-question');
  static const optionAKey = Key('poll-option-a');
  static const optionBKey = Key('poll-option-b');
  static const modeTabsKey = Key('poll-mode-tabs');
  static const oxTabKey = Key('poll-mode-tab-ox');
  static const customTabKey = Key('poll-mode-tab-custom');
  static const oxRingKey = Key('poll-mode-ring-ox');
  static const customRingKey = Key('poll-mode-ring-custom');

  @override
  ConsumerState<PollComposerScreen> createState() => _PollComposerScreenState();
}

class _PollComposerScreenState extends ConsumerState<PollComposerScreen> {
  final _text = TextEditingController();
  final _optionA = TextEditingController();
  final _optionB = TextEditingController();
  late final CommunityKind _kind = widget.kind ?? _kindFromAddress();

  CommunityComposerViewModel get _viewModel => ref.read(communityComposerViewModelProvider.notifier);

  CommunityKind _kindFromAddress() {
    final name = GoRouterState.of(context).uri.queryParameters['kind'];
    return CommunityKind.values.where((kind) => kind.name == name).firstOrNull ?? CommunityKind.poll;
  }

  @override
  void initState() {
    super.initState();
    // 그리는 중에는 provider 를 바꿀 수 없다 — 첫 프레임 뒤에 종류를 맞춘다(화면 모양은 처음부터 [_kind] 로 그린다).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewModel.selectKind(_kind);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _optionA.dispose();
    _optionB.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final posted = await _viewModel.submit();
    if (posted && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityComposerViewModelProvider);
    final l10n = context.l10n;
    final isPoll = _kind == CommunityKind.poll;
    final error = state.error;
    return Scaffold(
      // pen 앱바(손으로 그린 프레임): 56, 안쪽 [0,8] · 간격 4, 뒤로 48(arrow-left 22), 제목 x60 20/700.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: AppSpacing.xxs,
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
                ),
              )
            : null,
        title: Text(isPoll ? l10n.communityComposerTitle : l10n.communityComposerPostTitle, style: AppTypography.navTitle),
      ),
      body: SafeArea(
        // pen Body: 세로 간격 20, 안쪽 16. 버튼도 본문 흐름 안에 있다(화면 아래 고정 아님).
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _AnonymityNotice(),
            const SizedBox(height: _sectionGap),
            _CategorySection(selected: state.category, onSelected: _viewModel.selectCategory),
            // 칩 누름 영역 44 가 보이는 32 보다 아래로 6 더 크다 — 보이는 간격 20 을 지킨다(대장 판정 8).
            const SizedBox(height: _sectionGap - _CategorySection.hitOverhang),
            _FieldLabel(isPoll ? l10n.communityComposerQuestionLabel : l10n.communityComposerPostLabel),
            const SizedBox(height: AppSpacing.xs),
            _QuestionBox(
              controller: _text,
              maxLength: _kind.maxLength,
              minHeight: isPoll ? _pollBoxHeight : _postBoxHeight,
              hint: isPoll ? l10n.communityComposerQuestionHint : l10n.communityComposerPostHint,
              onChanged: _viewModel.updateText,
            ),
            const SizedBox(height: _sectionGap),
            if (isPoll) ...[_voteSection(state.usesDefaultOptions), const SizedBox(height: _sectionGap)],
            if (error != null) ...[
              // 하루 한도(429)면 서버가 준 문구 그대로(`RateLimitedFailure.serverMessage`).
              Text(context.errorText(error), style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.xs),
            ],
            AppButton(label: l10n.communityComposerSubmit, onPressed: state.canSubmit ? _submit : null),
          ],
        ),
      ),
    );
  }

  /// pen `VoteSection`: 세로 간격 12 — 라벨 14/600 #3F3F3F → 2칸 링 탭 줄(94) → 보기 줄(칸 사이 12) → 안내 글 12 muted lh1.5.
  Widget _voteSection(bool usesDefault) {
    final custom = !usesDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(context.l10n.communityComposerVoteMode),
        const SizedBox(height: AppSpacing.sm),
        _ModeTabs(usesDefault: usesDefault, onSelected: _viewModel.useDefaultOptions),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: custom ? _input(VoteSide.agree) : const VoteOption.mark(side: VoteSide.agree, interactive: false)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: custom ? _input(VoteSide.disagree) : const VoteOption.mark(side: VoteSide.disagree, interactive: false),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          custom ? context.l10n.communityComposerCustomHint : context.l10n.communityComposerOxHint,
          style: AppTypography.caption.copyWith(height: 1.5, color: AppColors.muted),
        ),
      ],
    );
  }

  /// pen `xlCc2`(파랑 · "보기 1") · `k9Bdo8`(빨강 · "보기 2").
  Widget _input(VoteSide side) {
    final isAgree = side == VoteSide.agree;
    final controller = isAgree ? _optionA : _optionB;
    return VoteOption.input(
      side: side,
      controller: controller,
      hint: isAgree ? context.l10n.communityComposerOption1 : context.l10n.communityComposerOption2,
      fieldKey: isAgree ? PollComposerScreen.optionAKey : PollComposerScreen.optionBKey,
      inputFormatters: [_maxCodePoints(pollOptionMaxLength)],
      onChanged: () => isAgree ? _viewModel.updateOptionA(controller.text) : _viewModel.updateOptionB(controller.text),
    );
  }
}

/// 칸 이름(pen Label `IwYG2` · TextInput 라벨): 14/600 #3F3F3F, 줄 높이 속성 없음 · 렌더 20.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTypography.labelSmall.copyWith(color: AppColors.body, height: 20 / 14));
}

/// 카테고리 고르기(pen CategorySection): 라벨 "카테고리" → 8 → 칩 셋(자유 · 진로 · 연애, 사이 8). 고르기 전에는 모두 Off.
/// 칩의 누름 영역(44)이 보이는 알약(32)보다 위아래로 6 씩 크다 — 위 간격은 여기서, 아래 간격은 부르는 쪽이 [hitOverhang] 만큼 줄인다.
class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.selected, required this.onSelected});

  final CommunityCategory? selected;
  final ValueChanged<CommunityCategory> onSelected;

  /// (누름 44 − 보임 32) / 2.
  static const double hitOverhang = 6;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(context.l10n.communityComposerCategoryLabel),
        const SizedBox(height: AppSpacing.xs - hitOverhang),
        // 글자를 키워 한 줄에 못 들어가면 다음 줄로 내린다.
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final category in CommunityCategory.values)
              CategoryChip(category: category, selected: category == selected, onTap: () => onSelected(category)),
          ],
        ),
      ],
    );
  }
}

/// pen `XC6KK`(17b 올리기 실패 `c9ch1w` 328×40): #F7F7F7, radius 10(토큰 밖), 안쪽 12, lock 16 + 12/600 muted.
class _AnonymityNotice extends StatelessWidget {
  const _AnonymityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          const Icon(AppIcons.lock, size: 16, color: AppColors.muted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.communityComposerAnonymityNotice,
              // 글자 상자 16(자물쇠와 같은 높이) — caption 토큰 16.8 이면 상자가 pen 40 보다 커진다.
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, height: 16 / 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Textarea 마스터 `Zhq9p`: #F7F7F7 · radius 8 · 테두리 #767676 1 · 안쪽 12 · 간격 4 · 최소 [minHeight],
/// 카운터 "n / 최대" 는 상자 안 아래 왼쪽. 투표 질문과 게시물 본문이 같이 쓴다.
class _QuestionBox extends StatelessWidget {
  const _QuestionBox({
    required this.controller,
    required this.maxLength,
    required this.minHeight,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int maxLength;
  final double minHeight;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final counterStyle = AppTypography.caption.copyWith(height: 1.5, color: AppColors.muted);
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.outline),
      ),
      // 카운터는 상자 아래에 붙인다(`Zhq9p`) — 글이 짧아도 상자 최소 높이의 바닥에 있다.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextField(
            key: PollComposerScreen.questionKey,
            controller: controller,
            inputFormatters: [_maxCodePoints(maxLength)],
            minLines: 2,
            maxLines: null,
            style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.ink),
            decoration: InputDecoration.collapsed(
              hintText: hint,
              hintStyle: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted),
            ),
            onChanged: onChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Text('${controller.text.runes.length} / $maxLength', style: counterStyle),
            ),
          ),
        ],
      ),
    );
  }
}

/// 투표 방식 탭 줄(pen 17b `u4UOb` · `tKjGJ` 의 KindTabs · StoryTab `CgYsy`): 폭 꽉 · 높이 94(위아래 4) · 탭 사이 12 · 왼쪽 정렬 ·
/// 아래 선 없음. 탭은 15d 피드와 같은 링 탭([PollRingTab], StoryTab `XfcKQ` 72×86) — O/X 는 3D 투표 · 직접 적기는 3D 편집.
class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.usesDefault, required this.onSelected});

  /// O/X 탭이면 true.
  final bool usesDefault;
  final ValueChanged<bool> onSelected;

  /// pen `CgYsy` 탭 사이 12 = [AppSpacing.sm].
  static const double _gap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: PollComposerScreen.modeTabsKey,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PollRingTab(
            tapKey: PollComposerScreen.oxTabKey,
            ringKey: PollComposerScreen.oxRingKey,
            label: 'O/X',
            icon: AppIcon3d.vote, // 3D 투표 `x5QLa`
            selected: usesDefault,
            onTap: () => onSelected(true),
          ),
          const SizedBox(width: _gap),
          PollRingTab(
            tapKey: PollComposerScreen.customTabKey,
            ringKey: PollComposerScreen.customRingKey,
            label: context.l10n.communityComposerModeCustom,
            icon: AppIcon3d.pencil, // 3D 편집 `DAILv`
            selected: !usesDefault,
            onTap: () => onSelected(false),
          ),
        ],
      ),
    );
  }
}
