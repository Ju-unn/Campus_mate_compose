import 'package:campus_mate/graduate/model/data/graduate_request_state.dart';
import 'package:campus_mate/graduate/view/graduate_reject_reason_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('반려 사유 글자 네 개는 앱 · 푸시 · 관리자 웹이 같은 글자다(대장 확정 D10) — 글자는 문구 파일(ARB)에서 온다', () {
    final l10n = AppLocalizationsKo();

    expect({for (final reason in GraduateRejectReason.values) reason: reason.label(l10n)}, {
      GraduateRejectReason.unreadable: '사진이 잘 안 보여요',
      GraduateRejectReason.notCertificate: '졸업증명서가 아니에요',
      GraduateRejectReason.unverifiable: '확인할 수 없는 번호예요',
      GraduateRejectReason.schoolUnsupported: '아직 지원하지 않는 학교예요',
    });
  });
}
