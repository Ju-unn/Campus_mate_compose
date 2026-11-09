import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/billing/task/view/heart_task_text.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

/// 반려 사유의 화면 글자(문구 파일 ARB, 1.0.2 B8). enum 은 서버 값만 들고, 글자는 view 쪽 확장이 정한다.
void main() {
  final l10n = AppLocalizationsKo();

  test('반려 사유 셋은 서버 푸시 문구(backend/app/admin/heart_task_notice.py)와 같은 글자다', () {
    expect({for (final reason in HeartTaskRejectReason.values) reason: reason.label(l10n)}, {
      HeartTaskRejectReason.dateMissing: '날짜가 안 보여요',
      HeartTaskRejectReason.notVerified: '게시글·공유가 확인되지 않아요',
      HeartTaskRejectReason.reused: '이미 쓴 캡처예요',
    });
  });
}
