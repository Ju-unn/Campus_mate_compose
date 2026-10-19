import 'dart:async';

import 'package:campus_mate/billing/model/everytime_form_link.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/view/heart_task_photo_slots.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/muted_text_button.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const String _guide = '스크린샷을 첨부하면 확인 후 하트를 드려요';

/// 안내 아래 인증 기준 캡션(12/400 muted). 종전엔 에브리타임만 "날짜가 보이게 찍어 주세요"(대장 09-28 (가), 계획서 편차 6) —
/// 사용자 결정 10-12 로 항목마다 기준을 적고, 날짜 안내는 에브리타임 기준에 합쳤다. pen 은 아직 옛 글자다(동기화 대기).
/// 승인은 운영자가 눈으로 본다 — 서버는 이 기준을 검사하지 않는다. 단톡방 인원은 10-16 사용자 확정으로 5명 → 3명.
String? _criteria(HeartTaskKind kind) => switch (kind) {
      HeartTaskKind.everytimePost => '앱 이름(CampusMate)이 들어간 홍보 글을 올리고, 올린 날짜가 보이게 찍어 주세요',
      HeartTaskKind.kakaoShare => '3명 이상이 있는 단톡방에 공유한 글과 단톡방 인원 수가 보이게 찍어 주세요',
      // 투표는 제출 화면이 없다(라우터가 18a 로 돌려보낸다).
      HeartTaskKind.pollVote => null,
    };
const String _retryCaption = '다시 찍어 올려 주세요';

/// 에브리타임 18b · 18b-2 보조 버튼(pen `F15q0W` · `DMrAI` TextButton, 대장 전달 값 10-17). 화살표는 아이콘이 아니라 글자다.
const String _formLabel = '에브리타임 양식 보기 →';

/// 낭독기는 화살표 대신 어디로 열리는지 읽는다.
const String _formSemanticsLabel = '에브리타임 양식 보기, 브라우저로 열려요';

/// 18b 경로. 반려 뒤 다시 낼 때는 사유를 `reason` 으로 실어 18b-2 알림을 띄운다.
String heartTaskSubmitLocation(HeartTaskKind kind, [HeartTaskRejectReason? reason]) => Uri(
      path: '${AppRoutes.heartTaskSubmit}/${kind.code}',
      queryParameters: reason == null ? null : {'reason': reason.code},
    ).toString();

/// 18b 인증샷 제출(pen `F15q0W`) · 18b-2 반려 뒤 다시 제출(`DMrAI`).
class HeartTaskSubmitScreen extends ConsumerStatefulWidget {
  const HeartTaskSubmitScreen({required this.kind, this.rejectReason, super.key});

  final HeartTaskKind kind;

  /// 반려 뒤 다시 내는 18b-2 면 있다 — 맨 위 알림(pen `kdibh`)과 버튼 글자가 바뀐다.
  final HeartTaskRejectReason? rejectReason;

  @override
  ConsumerState<HeartTaskSubmitScreen> createState() => _HeartTaskSubmitScreenState();
}

class _HeartTaskSubmitScreenState extends ConsumerState<HeartTaskSubmitScreen> {
  /// 04-2 사진 화면과 같은 3초.
  static const Duration _toastDuration = Duration(seconds: 3);

  String? _toast;
  Timer? _toastTimer;
  bool _openingForm = false;

  /// 한 번에 낼 수 있는 사진 수. 18a 가 읽어 둔 항목의 서버 값을 따르고(옛 서버는 1), 아직 못 읽었으면 3 이다.
  /// 처음에 한 번만 읽는다 — 제출이 실패해 18a 목록을 다시 읽는 동안 칸 수가 3 으로 튀지 않게.
  late final int _maxPhotos = _serverMaxPhotos();

  int _serverMaxPhotos() {
    final tasks = ref.read(heartTasksViewModelProvider).tasks;
    final max = tasks.where((task) => task.kind == widget.kind).map((task) => task.maxPhotos).firstOrNull ?? 0;
    return max > 0 ? max : HeartTaskSubmitUiState.defaultMaxPhotos;
  }

  /// 노션 양식은 앱 안 브라우저로 연다(설정 16 약관 줄과 같은 길, 10-16 사용자 결정 — open_url.dart).
  /// openInApp 은 예외만 false 로 돌려준다 — false 면 실패 토스트.
  Future<void> _openForm() async {
    if (_openingForm) return; // 여는 호출이 끝나기 전에 다시 눌러도 두 번 열지 않는다
    _openingForm = true;
    var opened = false;
    try {
      opened = await ref.read(openUrlProvider)(everytimeFormLink);
    } catch (_) {
      // 기기 쪽 오류 — 아래에서 안내한다.
    } finally {
      _openingForm = false;
    }
    if (!opened && mounted) _showToast(const UnknownFailure().toDisplayMessage());
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(heartTaskSubmitViewModelProvider, (previous, next) {
      if (next.submitted && previous?.submitted != true) {
        // 18b 를 18c 로 바꾼다 — 18c 에서 뒤로 가면 18a 로 돌아간다.
        context.pushReplacement(AppRoutes.heartTaskPending);
        return;
      }
      final message = next.errorMessage;
      if (message != null) _showToast(message);
    });
    final state = ref.watch(heartTaskSubmitViewModelProvider);
    final viewModel = ref.read(heartTaskSubmitViewModelProvider.notifier);
    final reason = widget.rejectReason;
    final toast = _toast;
    return Scaffold(
      // pen `k9nvth`: 17c 와 같은 규격 — 뒤로 `syyGc` 48(arrow-left 22), 제목 x60.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: AppSpacing.xxs,
        leading: Navigator.of(context).canPop()
            // 18a 와 같다 — Align 이 없으면 leading 칸이 56 으로 늘어나 pen `syyGc` 48×48(8,4)과 달라진다.
            ? Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(AppIcons.arrowLeft, size: 22, color: AppColors.ink),
                  ),
                ),
              )
            : null,
        title: Text('인증샷 제출', style: AppTypography.navTitle),
      ),
      body: SafeArea(
        // pen `re6T6`: 세로 간격 16, 안쪽 16.
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (reason != null) ...[_RejectReasonAlert(reason: reason), const SizedBox(height: AppSpacing.md)],
            // pen `qLG9R` 16/600 #3F3F3F, 줄높이 속성 없음 · 렌더 23.
            Text(_guide, style: AppTypography.bodyStrong.copyWith(color: AppColors.body, height: 23 / 16)),
            if (_criteria(widget.kind) case final criteria?) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(criteria, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            ],
            const SizedBox(height: AppSpacing.md),
            // pen `uvkY2`(3장) · `r7wOTV`(1장) — 안내 묶음과 [제출하기] 사이, 옛 업로더 `moNIO` 자리.
            HeartTaskPhotoSlots(
              photos: state.photos,
              maxPhotos: _maxPhotos,
              onAdd: () => viewModel.addPhotos(maxPhotos: _maxPhotos),
              onRemove: viewModel.removePhoto,
            ),
            const SizedBox(height: AppSpacing.md),
            // 단톡방에는 양식이 없다. 버튼 높이 48 은 MutedTextButton 최소값 — 글자를 키우면 늘어난다.
            if (widget.kind == HeartTaskKind.everytimePost) ...[
              Semantics(
                button: true,
                label: _formSemanticsLabel,
                excludeSemantics: true,
                onTap: _openForm,
                child: MutedTextButton(label: _formLabel, onPressed: _openForm),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (toast != null) ...[
              Center(
                child: AppToast(
                  leading: const Icon(AppIcons.alertTriangle, size: 16, color: AppColors.onInk),
                  label: toast,
                ),
              ),
              // 버튼과 간격 12(04-2 pen 실측).
              const SizedBox(height: AppSpacing.sm),
            ],
            AppButton(
              label: reason == null ? '제출하기' : '다시 제출하기',
              onPressed: state.canSubmit ? () => unawaited(viewModel.submit(widget.kind)) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 18b-2 반려 알림(pen Alert `kdibh`, 마스터 `teNRJ`). 모서리 없이 본문 폭을 채운다.
class _RejectReasonAlert extends StatelessWidget {
  const _RejectReasonAlert({required this.reason});

  final HeartTaskRejectReason reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.errorWash,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(AppIcons.alertTriangle, size: 20, color: AppColors.error),
          // pen 실측 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다.
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '반려 사유: ${reason.label}',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.error, height: 1.5),
                ),
                // pen 알림 높이 67 = 위아래 24 + 21 + 18 + 4.
                const SizedBox(height: AppSpacing.xxs),
                Text(_retryCaption, style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
