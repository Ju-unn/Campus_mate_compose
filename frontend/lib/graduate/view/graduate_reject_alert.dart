import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:flutter/material.dart';

/// 테스트가 반려 알림을 찾는 표식.
const Key graduateRejectAlertKey = ValueKey('graduate-reject-alert');

/// 반려 알림 첫 줄에 붙는 접두(pen `e49ej` "반려 사유: 졸업증명서가 아니에요").
const String _reasonPrefix = '반려 사유: ';

/// 알림 둘째 줄(pen `Gmb1H`) 앞머리. 값표는 사유 하나(졸업증명서가 아니에요)만 그려서, 대장 결정(10-19)으로
/// 모든 사유에 같은 줄을 쓰고 뒤에 남은 신청 횟수를 붙인다. 지원하지 않는 학교는 다시 올려 봐야 소용없어 다른 길을 알린다.
const String _retryCaption = '졸업증명서 사진을 다시 올려 주세요';
const String _unsupportedCaption = '뒤로 가서 학교 이메일로 인증할 수도 있어요';

/// 서버가 모르는 사유 코드를 주었거나 사유가 비었을 때(`reason == null`)의 한 줄. 값표에 없어 앱이 정한 문구다.
const String _unknownReasonTitle = '졸업증명서 확인이 반려됐어요';

/// 사유별 문구 — 대장 확정 D10(10-19): 앱 · 푸시 · 관리자 웹이 같은 글자 네 개를 쓴다. 앞 셋은 값표 §5 사유 예시 3개(pen 02-g-3),
/// 넷째 `school_unsupported` 는 시안에 없어 같은 틀로 추가했다(값표에 없어 임의).
/// 서버 푸시 문구(`backend/app/admin/graduate_notice.py` REASON_TEXT)도 같은 글자다(대장이 맞췄다).
const Map<GraduateRejectReason, String> graduateRejectReasonText = {
  GraduateRejectReason.unreadable: '사진이 잘 안 보여요',
  GraduateRejectReason.notCertificate: '졸업증명서가 아니에요',
  GraduateRejectReason.unverifiable: '확인할 수 없는 번호예요',
  GraduateRejectReason.schoolUnsupported: '아직 지원하지 않는 학교예요',
};

/// 02-g-3 맨 위 반려 알림(pen `parki` · 마스터 `teNRJ` Alert, 18b-2 `kdibh` 복사). 본문 폭을 꽉 채우고 모서리가 없다.
/// 폭 fill · 아이콘과 글 사이 10 · 안쪽 [12,16] · 바탕 errorWash. 제목 14/600 error 줄높이 1.5, 캡션 12 muted 줄높이 1.5,
/// 두 줄 사이 2(PNG 실측 — 알림 높이 64.67 = 24 + 21 + 18 + 2).
class GraduateRejectAlert extends StatelessWidget {
  const GraduateRejectAlert({required this.reason, required this.attemptsLeft, super.key});

  final GraduateRejectReason? reason;

  /// 남은 신청 횟수. 캡션 끝에 "· 남은 신청 n번" 으로 붙는다(한 줄에 안 들어가면 캡션만 두 줄로 접힌다).
  final int attemptsLeft;

  String get _caption {
    final lead = reason == GraduateRejectReason.schoolUnsupported ? _unsupportedCaption : _retryCaption;
    return '$lead · 남은 신청 $attemptsLeft번';
  }

  @override
  Widget build(BuildContext context) {
    final text = graduateRejectReasonText[reason];
    return Container(
      key: graduateRejectAlertKey,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(color: AppColors.errorWash),
      child: Row(
        children: [
          const Icon(AppIcons.alertTriangle, size: 20, color: AppColors.error),
          // pen 실측 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다(18b-2 와 같다).
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text == null ? _unknownReasonTitle : '$_reasonPrefix$text',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.error, height: 1.5),
                ),
                const SizedBox(height: 2),
                Text(_caption, style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
