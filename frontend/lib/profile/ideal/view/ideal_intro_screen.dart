import 'dart:async';

import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/back_exit/back_exit_scope.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/profile/ideal/viewmodel/ideal_intro_view_model.dart';
import 'package:campus_mate/profile/onboarding/view/onboarding_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 가입 06-1 앞에서만 이상형 들어가기를 먼저 보이고, 끝나면 [child](06-1)로 바꾼다. 라우터가 가입 06-1 경로에만 두른다 —
/// 프로필 수정의 [이상형 조건 수정](`/me/ideal-conditions`)에는 두르지 않는다.
/// 같은 경로 안에서 바꾸므로 들어가기는 뒤로 쌓이지 않는다 — 06-1 의 뒤로는 설문으로 간다.
class IdealIntroGate extends ConsumerStatefulWidget {
  const IdealIntroGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IdealIntroGate> createState() => _IdealIntroGateState();
}

class _IdealIntroGateState extends ConsumerState<IdealIntroGate> {
  late bool _showIntro;
  final GlobalKey _switcherKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final viewModel = ref.read(idealIntroViewModelProvider.notifier);
    _showIntro = viewModel.shouldShow();
    // 그리는 중에는 provider 를 바꿀 수 없어 첫 프레임 뒤에 "봤다" 를 남긴다.
    if (_showIntro) WidgetsBinding.instance.addPostFrameCallback((_) => viewModel.markSeen());
  }

  @override
  Widget build(BuildContext context) {
    // pen 에 두 화면 사이 전환 값이 없다 — 같은 경로 안이라 플랫폼 전환을 못 써서 `{motion.standard}` 로 겹쳐 바꾼다(확인 대상).
    final switcher = AnimatedSwitcher(
      key: _switcherKey,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.standard,
      switchInCurve: AppMotion.standardCurve,
      transitionBuilder: _fadeWithoutTaps,
      child: _showIntro ? _intro() : widget.child,
    );
    // 들어가기의 뒤로 받는 곳은 바깥에 두어 [_showIntro] 가 거짓이 되는 순간 빠지게 한다 — 페이드 220ms 동안 06-1 의 것과
    // 두 겹이면 시스템 뒤로 한 번에 둘 다 불린다. 감싸고 벗길 때 전환이 처음부터 다시 만들어지지 않게 [_switcherKey] 로 잇는다.
    if (!_showIntro) return switcher;
    return BackExitScope(onBack: _back, child: switcher);
  }

  /// 기본 페이드 그대로이되, 바뀌는 동안(투명도 1 미만)에는 들어오는 06-1 도 나가는 들어가기도 누름을 받지 않는다 —
  /// 자동 이동 직전에 누른 손가락이 페이드인하는 06-1 칩을 켜지 않게.
  static Widget _fadeWithoutTaps(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, faded) => IgnorePointer(ignoring: animation.value < 1, child: faded),
      child: FadeTransition(opacity: animation, child: child),
    );
  }

  /// 들어가기와 그 앱바의 뒤로는 06-1 과 같다(설문으로 한 단계).
  VoidCallback? get _back => onboardingBack(ref, isBusy: false);

  Widget _intro() {
    return IdealIntroScreen(
      key: const ValueKey('ideal-intro'),
      onDone: () => setState(() => _showIntro = false),
      onBack: _back,
    );
  }
}

/// 이상형 들어가기(datingApp.pen 25-B 3장 `lP32p` · `t66q5i` · `gzKOH`, UI값표_CT5Lq_11-24 §15).
/// 세 줄이 [_lineGap] 간격으로 아래에서 올라오고, 다 나오고 [_holdAfterLines] 뒤 [onDone] 을 부른다.
/// 화면 아무 데나 누르면 바로 부른다 — 타이머와 겹쳐도 한 번만 부른다. "동작 줄이기" 면 세 줄을 한 번에 보이고 [_reducedHold] 뒤.
/// 화면 읽기(낭독기)가 켜져 있으면 세 줄을 한 번에 보이고 혼자 넘어가지 않는다 — 누를 때만 넘어간다(홈 배너 · 흐르는 줄과 같은 규칙).
class IdealIntroScreen extends StatefulWidget {
  const IdealIntroScreen({required this.onDone, this.onBack, super.key});

  final VoidCallback onDone;
  final VoidCallback? onBack;

  @override
  State<IdealIntroScreen> createState() => _IdealIntroScreenState();
}

class _IdealIntroScreenState extends State<IdealIntroScreen> {
  // 움직임 값은 pen 설명 카드(값표 §15-2 아래)에서 왔다 — 맞는 토큰이 없는 간격 · 기다림은 이 화면 상수로 둔다.
  /// 줄과 줄 사이("줄 간격 700ms")
  static const Duration _lineGap = Duration(milliseconds: 700);

  /// 줄 하나가 올라오는 시간("약 400ms"). `{motion.emphasis}` 는 DESIGN §7 이 카드 등장 · 매칭 성사에만 쓰게 해서 쓰지 않는다
  static const Duration _lineRise = Duration(milliseconds: 400);

  /// 마지막 줄이 다 나온 뒤 넘어가기까지("약 1.2초")
  static const Duration _holdAfterLines = Duration(milliseconds: 1200);

  /// "동작 줄이기" 일 때 넘어가기까지("1.5초")
  static const Duration _reducedHold = Duration(milliseconds: 1500);

  /// 올라오는 거리 — 설명 카드 "살짝" 에 값이 없어 매칭 성사 제목(§7 `Entrance` 12)과 같게 했다
  static const double _rise = 12;

  /// 2/3 · 3/3 장에서 첫 줄 투명도(값표 §15-2)
  static const double _dimmed = 0.5;

  Timer? _dimTimer;
  Timer? _doneTimer;
  bool _firstDimmed = false;
  bool _done = false;
  bool _started = false;

  /// 세 줄을 처음부터 다 보인다 — 동작 줄이기이거나 화면 읽기일 때
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // 화면 읽기: 세 줄을 한 번에 보이고 혼자 넘어가는 타이머를 걸지 않는다
    if (MediaQuery.accessibleNavigationOf(context)) {
      _still = true;
      _firstDimmed = true;
      return;
    }
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _startReduced();
      return;
    }
    _startAnimated();
  }

  void _startAnimated() {
    _dimTimer = Timer(_lineGap, () => setState(() => _firstDimmed = true));
    _doneTimer = Timer(_lineGap * 2 + _lineRise + _holdAfterLines, _finish);
  }

  void _startReduced() {
    _firstDimmed = true;
    _doneTimer = Timer(_reducedHold, _finish);
  }

  /// 타이머와 누름이 겹쳐도 한 번만 넘어간다.
  void _finish() {
    if (_done) return;
    _done = true;
    _dimTimer?.cancel();
    _doneTimer?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _dimTimer?.cancel();
    _doneTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OnboardingAppBar(current: 0, total: 3, onBack: widget.onBack),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: SafeArea(top: false, child: Column(children: [Expanded(child: _body(context)), _footer(context)])),
      ),
    );
  }

  /// pen Body: 세로 · 가로 가운데, 안쪽 [0,24], 마스코트와 글 사이 32. 글자가 커져도 넘치지 않게 스크롤에 싼다.
  Widget _body(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 그림 교체 대기: pen i5Ud2(`mascot-female-reward.webp`)는 앱 assets 에 없어 같은 토끼 기본 그림을 임시로 쓴다(대장 판정 10).
            Center(child: Image.asset('assets/images/mascot-female.webp', width: 120, height: 120, excludeFromSemantics: true)),
            const SizedBox(height: AppSpacing.xl),
            ..._lines(context),
          ],
        ),
      ),
    );
  }

  /// pen Lines: 세로 gap 8, 가운데 정렬. 첫 줄은 Type · body muted, 둘째 · 셋째 줄은 Type · headline ink.
  List<Widget> _lines(BuildContext context) {
    final l10n = context.l10n;
    final body = AppTypography.body.copyWith(color: AppColors.muted);
    final headline = AppTypography.headline.copyWith(color: AppColors.ink);
    final aboutMe = _text(l10n.profileIdealIntroLineAboutMe, body);
    return [
      _line(0, AnimatedOpacity(opacity: _firstDimmed ? _dimmed : 1, duration: _lineRise, child: aboutMe)),
      const SizedBox(height: AppSpacing.xs),
      _line(1, _text(l10n.profileIdealIntroLineAboutThem, headline)),
      const SizedBox(height: AppSpacing.xs),
      _line(2, _text(l10n.profileIdealIntroLineTellUs, headline)),
    ];
  }

  Widget _line(int index, Widget child) {
    return Entrance(rise: _rise, duration: _lineRise, delay: _lineGap * index, enabled: !_still, child: child);
  }

  Widget _text(String text, TextStyle style) => Text(text, style: style, textAlign: TextAlign.center);

  /// pen Footer: 안쪽 [0,24,32,24], Type · caption muted 가운데.
  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
      child: Text(
        context.l10n.profileIdealIntroTapHint,
        style: AppTypography.caption.copyWith(color: AppColors.muted),
        textAlign: TextAlign.center,
      ),
    );
  }
}
