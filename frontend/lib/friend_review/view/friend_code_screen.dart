import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/model/friend_review.dart';
import 'package:campus_mate/friend_review/model/friend_review_errors.dart';
import 'package:campus_mate/friend_review/view/friend_review_compose_sheet.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_code_ui_state.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_code_view_model.dart';
import 'package:campus_mate/friend_review/viewmodel/friend_review_list_view_model.dart';
import 'package:campus_mate/friend_review/viewmodel/writable_friends_provider.dart';
import 'package:campus_mate/referral/viewmodel/referral_code_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 화면 문구 — pen 20f eShpy · a6jyqI · Q3xfwm · uovMC · Mi3ux.
const _title = '친구 코드로 리뷰 쓰기'; // pen KXDke
const _guide = '친구에게 받은 추천 코드를 입력하면\n그 친구에게 리뷰를 남길 수 있어요'; // pen EuSqG
const _fieldLabel = '친구 추천 코드'; // pen kZSO7/VCwQo
const _fieldHint = '예: K7M2QX'; // pen kZSO7/p3T9Jb
const _checkLabel = '확인'; // pen qDvfE/ifX9K
const _writeLabel = '리뷰 쓰기'; // pen N6ZsI/ifX9K
// 서버 404 "코드를 찾을 수 없어요" 에 할 일을 붙인 pen 문구(BIJ3a/XATaU).
const _notFoundMessage = '코드를 찾을 수 없어요. 다시 확인해 주세요.';
const _alreadyReviewedMessage = '이미 리뷰를 남긴 친구예요'; // pen m9xLE/XATaU

// 토큰에 없는 pen 값.
const double _boxHeight = 52; // pen TDM1r — 최소값(글자를 키우면 늘어난다, DESIGN §11.2)
const double _valueLineHeight = 23 / 16; // pen p3T9Jb 16, 줄높이 속성 없음 · 렌더 23
const double _labelLineHeight = 20 / 14; // pen VCwQo 14/600, 줄높이 속성 없음 · 렌더 20
const double _bodyBottom = 28; // pen DbHeF padding 아래 28
const double _resultGap = 20; // pen KOyXd gap(입력 묶음 → 친구 줄)

const ({FriendReviewListSource source, String? profileId}) _written =
    (source: FriendReviewListSource.written, profileId: null);

/// 20f 친구 코드로 리뷰 쓰기(pen `eShpy` 외 4). 15 지인 리뷰 칸 "리뷰 쓰기" 줄(`H9STF`)에서 push 로 연다.
/// 코드 확인 → 확인 성공이면 친구 줄 + "리뷰 쓰기" → 20b 시트(`NHcsP`, 코드로 저장). 남기고 오면 이미 쓴 친구(20f-3b)가 된다.
class FriendCodeScreen extends ConsumerWidget {
  const FriendCodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendCodeViewModelProvider);
    final viewModel = ref.read(friendCodeViewModelProvider.notifier);
    final friend = state.friend;
    return Scaffold(
      // pen KFsOf 56, 여백 [0,8], 간격 4 — 뒤로 CxNLg(B8pl1) 48(arrow-left 22 ink), 제목 x60(20b · 20e 앱바와 같은 모양).
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: AppSpacing.xxs,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          // leading 칸은 앱바 높이 56 으로 늘어난다 — 가운데 두어 누름칸을 pen 48×48(y4)로.
          child: Center(
            child: IconButton(
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
            ),
          ),
        ),
        // pen KXDke 20/700 ink lh1.5. 글자를 키워 남은 폭(284)을 넘으면 줄이지 자르지 않는다(홈 · 나 탭 앱바와 같다).
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_title, style: AppTypography.navTitle.copyWith(color: AppColors.ink)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          // pen DbHeF [0,24,28,24]. 버튼은 바닥 고정, 위 칸만 스크롤(키보드 · 글자 확대).
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, _bodyBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.xl), // pen dZSaU
                      // pen EuSqG 16/400 #3F3F3F lh1.6.
                      Text(_guide, style: AppTypography.body.copyWith(color: AppColors.body)),
                      const SizedBox(height: AppSpacing.xl), // pen YwNgx
                      _CodeField(state: state, onChanged: viewModel.changeCode, onDone: viewModel.check),
                      if (friend != null) ...[
                        const SizedBox(height: _resultGap),
                        // pen vqob4 · xpNBT = WritableFriendRow(gN7m3), 아바타 · 쓰기 끔.
                        WritableFriendRow(nickname: friend.nickname, university: friend.university, showInitial: false),
                      ],
                    ],
                  ),
                ),
              ),
              _bottomButton(context, ref, state),
            ],
          ),
        ),
      ),
    );
  }

  /// pen qDvfE(HE8FZ = AppButton 52 · r14 · 16/700). 확인 전엔 "확인", 확인 뒤엔 "리뷰 쓰기"(20f-3b 는 꺼짐).
  /// 확인 중은 pen 에 없다 — AppButton 의 도는 표시를 쓴다.
  static Widget _bottomButton(BuildContext context, WidgetRef ref, FriendCodeUiState state) {
    final friend = state.friend;
    if (friend != null) {
      return AppButton(label: _writeLabel, onPressed: state.canWrite ? () => _write(context, ref, friend) : null);
    }
    return AppButton(
      label: _checkLabel,
      isLoading: state.phase == FriendCodePhase.checking,
      onPressed: state.canCheck ? ref.read(friendCodeViewModelProvider.notifier).check : null,
    );
  }

  /// 20b 를 코드 방식으로 띄운다. 남겼으면 이미 쓴 친구로 바꾸고, 15 가 쥔 "쓴 리뷰" · 20e 기다리는 친구를 다시 읽는다(20e 쓰기와 같다).
  /// 남기지 않고 닫았으면 다시 확인한다 — 저장이 409 였거나 보내는 중에 닫았으면 이미 쓴 친구로 바뀐다.
  static Future<void> _write(BuildContext context, WidgetRef ref, FriendCodeMatch friend) async {
    final saved = await showFriendCodeReviewComposeSheet(context, friend);
    if (!context.mounted) return;
    if (saved != true) {
      await ref.read(friendCodeViewModelProvider.notifier).recheck();
      return;
    }
    ref.read(friendCodeViewModelProvider.notifier).markReviewed();
    ref.invalidate(writableFriendsProvider);
    ref.read(friendReviewListViewModelProvider(_written).notifier).refresh();
  }
}

/// 코드 칸(pen TextInput `PccKZ` 인스턴스 kZSO7 · BIJ3a · KnZS9 · m9xLE · mij9k): 라벨 → 8 → 상자 52 → 8 → 안내 줄.
/// 공용 [LabeledField] 와 같은 마스터지만 시계 · info 줄, 키보드 "완료", 낭독 알림이 필요해 여기서 그린다(common 은 고치지 않는다).
class _CodeField extends StatelessWidget {
  const _CodeField({required this.state, required this.onChanged, required this.onDone});

  final FriendCodeUiState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final note = _note(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_fieldLabel, style: AppTypography.labelSmall.copyWith(color: AppColors.body, height: _labelLineHeight)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          onChanged: onChanged,
          onSubmitted: (_) => onDone(),
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: const [_FriendCodeFormatter()],
          style: AppTypography.body.copyWith(color: AppColors.ink, height: _valueLineHeight),
          decoration: InputDecoration(
            hintText: _fieldHint,
            hintStyle: AppTypography.body.copyWith(color: AppColors.muted, height: _valueLineHeight),
            filled: true,
            fillColor: AppColors.surfaceSoft,
            constraints: const BoxConstraints(minHeight: _boxHeight),
            // 위아래는 (52 - 값 23) / 2 — 값이 상자 한가운데에 온다(basic_info_edit 와 같은 계산).
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: (_boxHeight - 23) / 2),
            // 404 만 빨간 2px(pen BIJ3a/TDM1r). 429 · 이미 쓴 친구는 테두리 기본(Mi3ux · m9xLE). 누르면 ink 2(LabeledField 와 같다).
            border: _border(AppColors.hairline),
            enabledBorder: _hasError ? _errorBorder : _border(AppColors.hairline),
            focusedBorder: _hasError ? _errorBorder : _focusBorder,
          ),
        ),
        ?note,
      ],
    );
  }

  bool get _hasError => state.phase == FriendCodePhase.notFound;

  /// 칸 아래 한 줄(pen ErrorRow `a1eaV`). 실패(pen 에 없음)는 20f-2 아이콘에 서버 문구, 테두리는 기본이다.
  static _CodeNote? _note(FriendCodeUiState state) => switch (state.phase) {
        FriendCodePhase.notFound => const _CodeNote(AppIcons.circleAlert, AppColors.error, _notFoundMessage),
        // pen Mi3ux/DOBgd Lucide "clock".
        FriendCodePhase.tryLater => const _CodeNote(AppIcons.clock, AppColors.error, friendCodeTryLaterMessage),
        FriendCodePhase.alreadyReviewed => const _CodeNote(AppIcons.info, AppColors.muted, _alreadyReviewedMessage),
        FriendCodePhase.failed => _CodeNote(AppIcons.circleAlert, AppColors.error, state.failureMessage ?? ''),
        _ => null,
      };

  static final OutlineInputBorder _errorBorder = _border(AppColors.error, width: 2);
  static final OutlineInputBorder _focusBorder = _border(AppColors.ink, width: 2);

  /// `gapPadding` 0 — 떠오르는 라벨 자리가 값 앞에 더 띄우지 않게(basic_info_edit 와 같다).
  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: BorderSide(color: color, width: width),
      gapPadding: 0,
    );
  }
}

/// 칸 아래 안내 줄(pen `a1eaV` gap 4 · `DOBgd` 14 · `XATaU` 12/400): 칸 아래 8. 바뀌면 낭독기가 바로 읽는다(liveRegion).
class _CodeNote extends StatelessWidget {
  const _CodeNote(this.icon, this.color, this.text);

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(child: Text(text, style: AppTypography.caption.copyWith(color: color))),
          ],
        ),
      ),
    );
  }
}

/// 붙여 넣은 " k7 m-2qx " 도 같은 코드로 — 대문자로 바꾸고 영숫자만 남겨 코드 길이(6)까지. 최종 검증은 서버가 한다.
/// 공유 문구 전체(`inviteShareText`)를 붙이면 "추천 코드" 바로 뒤 토큰만 쓴다 — 앞의 "CampusMate" 를 코드로 고르지 않게(대장 10-13).
/// 한글은 칸에 남지 않아 "추천 코드" 는 붙여 넣을 때만 보인다.
class _FriendCodeFormatter extends TextInputFormatter {
  const _FriendCodeFormatter();

  static final RegExp _notCode = RegExp('[^A-Z0-9]');
  static final RegExp _afterLabel = RegExp(r'추천 코드\s*([A-Za-z0-9]*)');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final source = _afterLabel.firstMatch(newValue.text)?.group(1) ?? newValue.text;
    final cleaned = source.toUpperCase().replaceAll(_notCode, '');
    final text = cleaned.length > referralCodeLength ? cleaned.substring(0, referralCodeLength) : cleaned;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
