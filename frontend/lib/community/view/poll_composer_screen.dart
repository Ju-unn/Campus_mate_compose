import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
import 'package:campus_mate/community/view/vote_option.dart';
import 'package:campus_mate/community/viewmodel/community_feed_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 하루 10개를 넘겼을 때(서버 `POLL_DAILY_LIMIT` 과 같은 문구, 사용자 결정 3).
/// 429 는 공용 분류가 "너무 많이 시도했어요" 로 바꾸므로 이 화면이 문구를 바꿔 낀다.
const String pollDailyLimitMessage = '오늘은 질문을 더 올릴 수 없어요';

/// 글자 수는 서버(`len`) · DB(`char_length`)와 같은 **유니코드 코드 포인트** 로 센다.
/// Flutter `maxLength` 는 글자 모양(그래핌) 단위라 이모지(👍🏻 = 2)가 섞이면 앱은 통과시키고 서버가 422 를 낸다.
TextInputFormatter _maxCodePoints(int max) => TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.runes.length <= max) return newValue;
      final text = String.fromCharCodes(newValue.text.runes.take(max));
      return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    });

/// 투표 방식 탭(pen `O0ZJi` 의 두 칸). O/X 는 "찬성"/"반대" 를 보내 카드가 O·X 아이콘을 그린다.
enum _VoteMode { ox, custom }

/// 17b `poll-composer`(pen `tKjGJ` O/X · `Xe28J` 직접 적기). 입력 상태가 이 화면 안에서 끝나 ViewModel 을 두지 않는다.
class PollComposerScreen extends ConsumerStatefulWidget {
  const PollComposerScreen({super.key});

  static const questionKey = Key('poll-question');
  static const optionAKey = Key('poll-option-a');
  static const optionBKey = Key('poll-option-b');
  static const modeTabsKey = Key('poll-mode-tabs');
  static const oxTabKey = Key('poll-mode-tab-ox');
  static const customTabKey = Key('poll-mode-tab-custom');
  static const oxUnderlineKey = Key('poll-mode-underline-ox');
  static const customUnderlineKey = Key('poll-mode-underline-custom');

  @override
  ConsumerState<PollComposerScreen> createState() => _PollComposerScreenState();
}

class _PollComposerScreenState extends ConsumerState<PollComposerScreen> {
  final _question = TextEditingController();
  final _optionA = TextEditingController();
  final _optionB = TextEditingController();
  _VoteMode _mode = _VoteMode.ox;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    _optionA.dispose();
    _optionB.dispose();
    super.dispose();
  }

  /// O/X 탭은 보기가 정해져 있어 늘 맞다. 직접 적기 탭은 둘 다 적고 서로 달라야 한다(서버 규칙과 같다).
  String get _optionTextA => _mode == _VoteMode.ox ? defaultOptionA : _optionA.text.trim();
  String get _optionTextB => _mode == _VoteMode.ox ? defaultOptionB : _optionB.text.trim();

  bool get _canSubmit {
    final a = _optionTextA;
    final b = _optionTextB;
    return !_isSubmitting && _question.text.trim().isNotEmpty && a.isNotEmpty && b.isNotEmpty && a != b;
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ref.read(communityRepositoryProvider).createPoll(
          question: _question.text.trim(),
          optionA: _optionTextA,
          optionB: _optionTextB,
        );
    if (!mounted) return;
    result.when(
      onSuccess: (_) {
        ref.read(communityFeedViewModelProvider.notifier).refresh();
        context.pop();
      },
      onFailure: (failure) => setState(() {
        _isSubmitting = false;
        _error = failure is RateLimitedFailure ? pollDailyLimitMessage : failure.toDisplayMessage();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // pen `jrUTh`: 56, 안쪽 [0,8] · 간격 4, 뒤로 `g58njs` 48(arrow-left 22), 제목 `RKulj` x60.
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
        title: Text('익명으로 질문하기', style: AppTypography.navTitle),
      ),
      body: SafeArea(
        // pen `QhlmU`: 세로 간격 20, 안쪽 16. 버튼도 본문 흐름 안에 있다(화면 아래 고정 아님).
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _AnonymityNotice(),
            const SizedBox(height: 20),
            // pen `BxeOU/VCwQo` 14/600 #3F3F3F, 줄 높이 속성 없음 · 렌더 20.
            Text('질문 내용', style: AppTypography.labelSmall.copyWith(color: AppColors.body, height: 20 / 14)),
            const SizedBox(height: AppSpacing.xs),
            _QuestionBox(controller: _question, onChanged: () => setState(() {})),
            const SizedBox(height: 20),
            _voteSection(),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.xs),
            ],
            AppButton(label: '익명으로 올리기', onPressed: _canSubmit ? _submit : null),
          ],
        ),
      ),
    );
  }

  /// pen `VoteSection`: 세로 간격 12 — 라벨 14/600 #3F3F3F → 2칸 탭 → 보기 줄(칸 사이 12) → 안내 글 12 muted lh1.5.
  Widget _voteSection() {
    final custom = _mode == _VoteMode.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('투표 방식', style: AppTypography.labelSmall.copyWith(color: AppColors.body, height: 20 / 14)),
        const SizedBox(height: AppSpacing.sm),
        _ModeTabs(mode: _mode, onSelected: (mode) => setState(() => _mode = mode)),
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
          custom ? '보기 글자는 1~6자, 서로 달라야 해요' : 'O = 찬성, X = 반대로 투표를 받아요',
          style: AppTypography.caption.copyWith(height: 1.5, color: AppColors.muted),
        ),
      ],
    );
  }

  /// pen `xlCc2`(파랑 · "보기 1") · `k9Bdo8`(빨강 · "보기 2").
  Widget _input(VoteSide side) {
    final isAgree = side == VoteSide.agree;
    return VoteOption.input(
      side: side,
      controller: isAgree ? _optionA : _optionB,
      hint: isAgree ? '보기 1' : '보기 2',
      fieldKey: isAgree ? PollComposerScreen.optionAKey : PollComposerScreen.optionBKey,
      inputFormatters: [_maxCodePoints(pollOptionMaxLength)],
      onChanged: () => setState(() {}),
    );
  }
}

/// pen `XC6KK`: #F7F7F7, radius 10(토큰 밖), 안쪽 12, lock 16 + 12/600 muted.
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
              '작성자 정보는 절대 공개되지 않아요',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Textarea 마스터 `Zhq9p`: #F7F7F7 · radius 8 · 테두리 #767676 1 · 안쪽 12 · 간격 4 · 최소 104,
/// 카운터 "0 / 80" 은 상자 안 아래 왼쪽. 라벨 · 자리글 문구는 17b `p4wnJ` 값이다(대장 지시로 두 값을 합친다).
class _QuestionBox extends StatelessWidget {
  const _QuestionBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final counterStyle = AppTypography.caption.copyWith(height: 1.5, color: AppColors.muted);
    return Container(
      constraints: const BoxConstraints(minHeight: 100), // 17b 질문 상자 100(대장 10-08, 옛 104)
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
            inputFormatters: [_maxCodePoints(pollQuestionMaxLength)],
            minLines: 2,
            maxLines: null,
            style: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.ink),
            decoration: InputDecoration.collapsed(
              hintText: '예) 깻잎을 먼저 집으면 안 되는 거 아니야?',
              hintStyle: AppTypography.bodySmall.copyWith(height: 1.5, color: AppColors.muted),
            ),
            onChanged: (_) => onChanged(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text('${controller.text.runes.length} / $pollQuestionMaxLength', style: counterStyle),
          ),
        ],
      ),
    );
  }
}

/// pen Tab Bar `O0ZJi` 의 두 칸: 높이 44(글자를 키우면 따라 자란다), 아래 선 #EBEBEB 1.
class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onSelected});

  final _VoteMode mode;
  final ValueChanged<_VoteMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: PollComposerScreen.modeTabsKey,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.hairlineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              tabKey: PollComposerScreen.oxTabKey,
              underlineKey: PollComposerScreen.oxUnderlineKey,
              label: 'O/X',
              selected: mode == _VoteMode.ox,
              onTap: () => onSelected(_VoteMode.ox),
            ),
          ),
          Expanded(
            child: _ModeTab(
              tabKey: PollComposerScreen.customTabKey,
              underlineKey: PollComposerScreen.customUnderlineKey,
              label: '직접 적기',
              selected: mode == _VoteMode.custom,
              onTap: () => onSelected(_VoteMode.custom),
            ),
          ),
        ],
      ),
    );
  }
}

/// 탭 칸(pen `Tab` `H2Qyx`): 위 안쪽 12, 선택 = #C4224B 700 + 밑줄 2 / 비선택 = #6A6A6A 500 + 밑줄 투명.
class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.tabKey,
    required this.underlineKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key tabKey;
  final Key underlineKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double _barHeight = 44;
  static const double _underline = 2;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelSmall.copyWith(
      color: selected ? AppColors.primaryText : AppColors.muted,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      height: 20 / 14,
    );
    // 투명 Material 이 눌림 효과를 받는다 — 없으면 가장 가까운 Material 이 화면 전체 Scaffold 라 효과가 화면에 번진다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: tabKey,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _barHeight - _underline),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Align(alignment: Alignment.topCenter, heightFactor: 1, child: Text(label, style: style)),
                ),
              ),
              SizedBox(
                height: _underline,
                child: ColoredBox(key: underlineKey, color: selected ? AppColors.primaryText : Colors.transparent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
