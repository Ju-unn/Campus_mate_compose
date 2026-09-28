import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/model/cohort_wait.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// 테스트가 시계를 바꿔 끼운다.
final homeNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 휴대폰 공유 창(계획서 결정 5). 테스트는 받은 글을 모은다.
final shareTextProvider = Provider<Future<void> Function(String)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// "D-14" · 당일은 "D-day"(계획서 결정 8). 기기 시간대의 달력 날짜로 센다 —
/// 시각 차이 `inDays` 는 06:59 와 07:00 사이에서 하루가 틀린다.
String cohortDayLabel(DateTime now, DateTime opensAt) {
  final days = DateTime.utc(opensAt.year, opensAt.month, opensAt.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
  return days <= 0 ? 'D-day' : 'D-$days';
}

/// 큰 줄: 당일은 "오늘 오전 7시", 그 전은 "9월 23일"(결정 8). 시각은 7 을 박지 않고 여는 시각에서 읽는다.
String cohortDateLabel(DateTime now, DateTime opensAt) {
  if (cohortDayLabel(now, opensAt) != 'D-day') return '${opensAt.month}월 ${opensAt.day}일';
  final h = opensAt.hour;
  final minute = opensAt.minute == 0 ? '' : ' ${opensAt.minute}분';
  return '오늘 ${h < 12 ? '오전' : '오후'} ${h % 12 == 0 ? 12 : h % 12}시$minute';
}

/// 19 코호트 대기(pen `tUaGw`) 본문. 앱바 · 하단 내비는 부르는 화면 것을 그대로 쓴다(Q2 (가)).
/// 초마다 돌지 않는다 — 다음 자정(D-숫자)과 여는 시각(요약 다시 읽기) 중 먼저 오는 쪽에 타이머 하나.
class CohortWaitView extends ConsumerStatefulWidget {
  const CohortWaitView({required this.cohort, super.key});

  final CohortWait cohort;

  @override
  ConsumerState<CohortWaitView> createState() => _CohortWaitViewState();
}

class _CohortWaitViewState extends ConsumerState<CohortWaitView> {
  Timer? _timer;

  /// 폰이 잠든 시간은 타이머 시계에 안 잡힐 수 있다 — 앱으로 돌아오면 지금 시각으로 다시 센다.
  late final AppLifecycleListener _lifecycle;

  /// 코드를 기다리는 동안 다시 눌러도 공유 창을 두 번 열지 않는다.
  bool _inviting = false;

  /// 지금 떠 있는 안내. `photos_screen` 과 같은 방식 — 한 번에 하나, 3초.
  String? _toast;
  Timer? _toastTimer;
  static const Duration _toastDuration = Duration(seconds: 3);

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _invite() async {
    if (_inviting) return;
    _inviting = true;
    try {
      final result = await ref.read(referralRepositoryProvider).myCode();
      if (!mounted) return;
      await result.when<Future<void>>(
        // 공유 글은 계획서 결정 5 제안. 하트 숫자 · 스토어 링크는 넣지 않는다.
        onSuccess: (code) => ref.read(shareTextProvider)('CampusMate 에서 같이 해요! 가입할 때 추천 코드 $code 를 넣어 줘.'),
        onFailure: (failure) async => _showToast(failure.toDisplayMessage()),
      );
    } catch (_) {
      // 공유 창을 못 열었다(기기 쪽 오류). 조용히 끝내지 않는다.
      if (mounted) _showToast(const UnknownFailure().toDisplayMessage());
    } finally {
      _inviting = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _schedule();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    // 잠든 사이 여는 시각이 지났으면 곧바로 다시 읽는다(1분 기다리지 않게). 아니면 D-숫자만 다시 센다.
    if (!ref.read(homeNowProvider)().isBefore(widget.cohort.firstCardAt)) ref.invalidate(homeSummaryProvider);
    setState(_schedule);
  }

  @override
  void didUpdateWidget(CohortWaitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다시 읽은 요약이 다른 여는 시각을 가져오면(운영자가 날짜를 바꿈) 타이머를 새로 건다.
    if (oldWidget.cohort.firstCardAt != widget.cohort.firstCardAt) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _toastTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final now = ref.read(homeNowProvider)();
    final opensAt = widget.cohort.firstCardAt;
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final opening = !midnight.isBefore(opensAt);
    var wait = (opening ? opensAt : midnight).difference(now);
    // 기기 시계가 서버보다 빠르면 다시 읽어도 cohort 가 온다 — 0초로 되풀이해 서버를 두드리지 않게.
    if (wait <= Duration.zero) wait = const Duration(minutes: 1);
    _timer = Timer(wait, () {
      // 열렸으면 요약이 cohort 없이 와서 이 화면이 09b 로 바뀐다(이 위젯이 사라지며 타이머도 끝).
      // 아직 cohort 면 1분 뒤 다시 읽는다.
      if (opening) ref.invalidate(homeSummaryProvider);
      setState(_schedule);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(homeNowProvider)();
    final opensAt = widget.cohort.firstCardAt;
    return CustomScrollView(
      slivers: [
        // 보통 글자에선 버튼이 아래에 붙고(pen), 글자를 키워 넘치면 같이 스크롤된다.
        SliverFillRemaining(
          hasScrollBody: false,
          // pen `R1DPu` padding [8,16,24,16], gap 20. SliverPadding 으로 감싸면 채움 높이가 아래 24 를 빼지 않아
          // 버튼이 내비에 붙는다 — 그래서 안쪽 Padding 이다.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(dayLabel: cohortDayLabel(now, opensAt), dateLabel: cohortDateLabel(now, opensAt)),
                const SizedBox(height: 20),
                _RecruitPanel(count: widget.cohort.recruitCount),
                const SizedBox(height: 20),
                // `G5OV3t` 14/400 #3F3F3F lh1.5 — 문구는 PNG 08.
                Text(
                  '친구와 함께 시작하면 첫날부터 더 많은 캠퍼스 친구를 만날 수 있어요.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5),
                ),
                const Spacer(),
                const SizedBox(height: 20),
                // 토스트 자리는 pen 에 없어 photos_screen 과 같이 버튼 위 가운데, 간격 12 로 둔다.
                if (_toast != null) ...[
                  Center(
                    child: AppToast(
                      leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                      label: _toast!,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _InviteButton(onPressed: _invite),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 히어로(pen `gFbj2`) 328×330 · 안쪽 [20,20,18,20] · gap 8. 내용은 위에서부터 채운다(PNG 08).
class _Hero extends StatelessWidget {
  const _Hero({required this.dayLabel, required this.dateLabel});

  final String dayLabel;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    // 330 은 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 330),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        children: [
          // `of3fj` = 마스코트 male.
          Image.asset('assets/images/mascot-male.png', width: 132, height: 132),
          const SizedBox(height: 8),
          // `BBGsm` 14/600 #C4224B lh1.5. " · D-14" 는 Q1 (가) — 48 한 줄에 넣으면 폭이 모자란다.
          Text(
            '우리 학교 첫 카드까지 · $dayLabel',
            textAlign: TextAlign.center,
            style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText, height: 1.5),
          ),
          const SizedBox(height: 8),
          // `IDJ3M` 48/700 #222222 lh1.5(토큰 1.1). "오늘 오전 7시" · 긴 날짜 · 글자 확대에도 폭을 넘지 않게 줄여 보인다.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(dateLabel, style: AppTypography.countdown.copyWith(color: AppColors.ink, height: 1.5)),
          ),
          const SizedBox(height: 8),
          // `ocR77` 14/400 #6A6A6A.
          Text(
            '같은 날, 같은 설렘으로 시작해요',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 모집 판(pen `u7XsyB`) 92h #F7F7F7 r14 padding 16. 목표 배지 `R6EEu` 는 Q3 (가)로 뺐다.
class _RecruitPanel extends StatelessWidget {
  const _RecruitPanel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // 92 는 최소 높이다 — 글자를 키우면 늘어난다(DESIGN §11.2).
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `WEPFQ` 14/400 #6A6A6A · `ebHk4` 24/700 #222222.
          Text('현재 모집 인원', style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
          Text('$count명', style: AppTypography.headline.copyWith(color: AppColors.ink)),
        ],
      ),
    );
  }
}

/// 친구 초대(pen `FftE4`) — 일반 frame 52h r8(계획서 결정 10, `AppButton` 56h r16 아님).
class _InviteButton extends StatelessWidget {
  const _InviteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ).copyWith(
        // 눌림 효과는 번짐 대신 배경색으로(COMMON §4-2, AppButton 과 같은 규칙).
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed) ? AppColors.primaryPressed : AppColors.primary,
        ),
        foregroundColor: const WidgetStatePropertyAll(AppColors.onPrimary),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      child: Text(
        '친구에게 초대 링크 보내기',
        textAlign: TextAlign.center,
        style: AppTypography.label.copyWith(color: AppColors.onPrimary),
      ),
    );
  }
}
