import 'dart:async';
import 'dart:io';

import 'package:campus_mate/billing/model/everytime_form_link.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/muted_text_button.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
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
const String _uploaderLabel = '스크린샷 첨부하기';
const String _retryCaption = '다시 찍어 올려 주세요';

/// 에브리타임 18b · 18b-2 보조 버튼(pen `F15q0W` · `DMrAI` TextButton, 대장 전달 값 10-17). 화살표는 아이콘이 아니라 글자다.
const String _formLabel = '에브리타임 양식 보기 →';

/// 낭독기는 화살표 대신 어디로 열리는지 읽는다.
const String _formSemanticsLabel = '에브리타임 양식 보기, 브라우저로 열려요';

/// 테스트가 업로더를 찾는 표식.
const Key heartTaskUploaderKey = ValueKey('heart-task-uploader');

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
            _ProofUploader(photo: state.photo, onTap: state.isSubmitting ? null : viewModel.pickPhoto),
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

/// 업로더(pen `moNIO` 인스턴스 `u7vbr`). 고른 뒤에는 같은 칸에 사진을 통째로 보여 준다(DESIGN §8.10 "fit",
/// pen 에 채운 상태 없음 — 편차 3). 잉크는 업로더 자신의 Material 에 그린다(COMMON §4-2).
class _ProofUploader extends StatelessWidget {
  const _ProofUploader({required this.photo, required this.onTap});

  final File? photo;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    final onTap = this.onTap;
    return Material(
      key: heartTaskUploaderKey,
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null ? null : () => unawaited(onTap()),
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: photo == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // pen `C1BBE` 3D 업로드 70(ref `CR3C7`, 값표 1004).
                    const Icon3d(AppIcon3d.upload, size: 70),
                    const SizedBox(height: AppSpacing.xs),
                    // pen WmkOO 14/600 muted, 줄높이 속성 없음 · 렌더 20.
                    Text(
                      _uploaderLabel,
                      style: AppTypography.labelSmall.copyWith(color: AppColors.muted, height: 20 / 14),
                    ),
                  ],
                )
              : Image.file(photo, fit: BoxFit.contain, semanticLabel: _uploaderLabel),
        ),
      ),
    );
  }
}
