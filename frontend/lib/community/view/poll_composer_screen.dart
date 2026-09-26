import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/community/model/community_repository_provider.dart';
import 'package:campus_mate/community/model/poll.dart';
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

/// 17b `poll-composer`(pen `p4wnJ`). 입력 상태가 이 화면 안에서 끝나 ViewModel 을 두지 않는다.
class PollComposerScreen extends ConsumerStatefulWidget {
  const PollComposerScreen({super.key});

  static const questionKey = Key('poll-question');
  static const optionAKey = Key('poll-option-a');
  static const optionBKey = Key('poll-option-b');

  @override
  ConsumerState<PollComposerScreen> createState() => _PollComposerScreenState();
}

class _PollComposerScreenState extends ConsumerState<PollComposerScreen> {
  final _question = TextEditingController();
  final _optionA = TextEditingController(text: defaultOptionA);
  final _optionB = TextEditingController(text: defaultOptionB);
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    _optionA.dispose();
    _optionB.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final a = _optionA.text.trim();
    final b = _optionB.text.trim();
    return !_isSubmitting && _question.text.trim().isNotEmpty && a.isNotEmpty && b.isNotEmpty && a != b;
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final result = await ref.read(communityRepositoryProvider).createPoll(
          question: _question.text.trim(),
          optionA: _optionA.text.trim(),
          optionB: _optionB.text.trim(),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _optionField('선택지 A', PollComposerScreen.optionAKey, _optionA)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _optionField('선택지 B', PollComposerScreen.optionBKey, _optionB)),
              ],
            ),
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

  /// pen `mYKYP`: 라벨 12/600 · 간격 6 · 상자 44 #F7F7F7 radius 8 [0,14] 테두리 없음 · 값 14/600.
  Widget _optionField(String label, Key key, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.body)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: TextField(
            key: key,
            controller: controller,
            inputFormatters: [_maxCodePoints(pollOptionMaxLength)],
            style: AppTypography.labelSmall.copyWith(color: AppColors.ink),
            decoration: const InputDecoration.collapsed(hintText: ''),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
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
      constraints: const BoxConstraints(minHeight: 104),
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
