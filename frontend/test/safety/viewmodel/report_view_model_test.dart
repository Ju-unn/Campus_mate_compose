import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/safety/model/report_reason.dart';
import 'package:campus_mate/safety/model/safety_repository.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:campus_mate/safety/viewmodel/report_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_safety_repository.dart';

void main() {
  late FakeSafetyRepository repository;
  late ProviderContainer container;

  const target = ReportTarget.message('msg-7');

  setUp(() {
    repository = FakeSafetyRepository();
    container = ProviderContainer(
      overrides: [safetyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    // autoDispose 라 누군가 보고 있어야 상태가 남는다 — 시트가 떠 있는 동안과 같다.
    container.listen(reportViewModelProvider, (_, _) {});
  });

  ReportViewModel viewModel() => container.read(reportViewModelProvider.notifier);
  ReportUiState state() => container.read(reportViewModelProvider);

  group('신고하기 버튼', () {
    test('사유를 고르기 전에는 누를 수 없다', () {
      expect(state().canSubmit, isFalse);
    });

    test('기타가 아닌 사유를 고르면 메모 없이 누를 수 있다', () {
      viewModel().selectReason(ReportReason.spam);

      expect(state().canSubmit, isTrue);
    });

    test('기타는 메모가 공백뿐이면 누를 수 없고, 글자가 있으면 누를 수 있다', () {
      viewModel()
        ..selectReason(ReportReason.other)
        ..updateNote('   ');
      expect(state().canSubmit, isFalse);

      viewModel().updateNote(' 외부 링크 ');
      expect(state().canSubmit, isTrue);
    });

    test('보내는 중에는 누를 수 없고, 두 번 눌러도 한 번만 보낸다', () async {
      repository.holdReport = Completer<void>();
      viewModel().selectReason(ReportReason.abuse);

      final first = viewModel().submit(target);
      expect(state().isSubmitting, isTrue);
      expect(state().canSubmit, isFalse);
      await viewModel().submit(target);

      repository.holdReport!.complete();
      await first;
      expect(repository.reports, hasLength(1));
    });

    test('보내는 중에 시트를 닫아 버려도 응답이 왔을 때 터지지 않는다', () async {
      repository.holdReport = Completer<void>();
      final sheet = ProviderContainer(
        overrides: [safetyRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = sheet.listen(reportViewModelProvider, (_, _) {});
      final notifier = sheet.read(reportViewModelProvider.notifier)
        ..selectReason(ReportReason.abuse);

      final pending = notifier.submit(target);
      // 사용자가 시트를 아래로 밀어 닫았다 — 보던 쪽이 없어져 autoDispose 가 버린다.
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      repository.holdReport!.complete();

      await expectLater(pending, completes);
      sheet.dispose();
    });
  });

  group('보낸 결과', () {
    test('성공하면 신고됨으로 끝나고 차단 안내 문구를 준다', () async {
      viewModel()
        ..selectReason(ReportReason.other)
        ..updateNote('외부 링크');

      await viewModel().submit(target);

      expect(state().outcome, ReportOutcome.reported);
      expect(state().closingMessage, reportedMessage);
      expect(state().isSubmitting, isFalse);
      final sent = repository.reports.single;
      expect(sent.target, {'target_type': 'message', 'target_id': 'msg-7'});
      expect(sent.reason, ReportReason.other);
      expect(sent.note, '외부 링크');
    });

    test('409 이미 신고함은 끝난 것으로 친다', () async {
      repository.reportResult = const FailureResult(ServerRejectedFailure('이미 신고를 완료했어요'));
      viewModel().selectReason(ReportReason.abuse);

      await viewModel().submit(target);

      expect(state().outcome, ReportOutcome.alreadyReported);
      expect(state().closingMessage, '이미 신고를 완료했어요');
      expect(state().errorMessage, isNull);
    });

    test('429 하루 상한이면 오늘은 더 못 한다고 알리고 끝낸다', () async {
      repository.reportResult = const FailureResult(RateLimitedFailure());
      viewModel().selectReason(ReportReason.abuse);

      await viewModel().submit(target);

      expect(state().outcome, ReportOutcome.limited);
      expect(state().closingMessage, '오늘은 더 신고할 수 없어요');
    });

    test('404 대상이 사라졌으면 서버 문구 그대로 알리고 끝낸다', () async {
      repository.reportResult = const FailureResult(ServerRejectedFailure('메시지를 찾을 수 없어요'));
      viewModel().selectReason(ReportReason.abuse);

      await viewModel().submit(target);

      expect(state().outcome, ReportOutcome.targetGone);
      expect(state().closingMessage, '메시지를 찾을 수 없어요');
    });

    test('그 밖의 실패는 끝내지 않고 문구만 띄워 다시 보낼 수 있게 둔다', () async {
      repository.reportResult = const FailureResult(NetworkFailure());
      viewModel().selectReason(ReportReason.abuse);

      await viewModel().submit(target);

      expect(state().outcome, isNull);
      expect(state().errorMessage, '네트워크 연결을 확인해 주세요');
      expect(state().isSubmitting, isFalse);
      expect(state().canSubmit, isTrue);
    });

    test('실패 뒤 다시 보내면 같은 요청이 가고, 성공하면 문구가 지워진다', () async {
      // 서버는 차단을 먼저 하므로 첫 요청에서 차단만 되고 신고가 실패했을 수 있다 —
      // 그때 진입점(방 · 14c)이 사라져 있어 이 시트에서 다시 보내는 것이 유일한 길이다(계획서 A1).
      repository.reportResult = const FailureResult(ServerUnavailableFailure());
      viewModel().selectReason(ReportReason.fake);
      await viewModel().submit(target);

      repository.reportResult = const Success(null);
      await viewModel().submit(target);

      expect(repository.reports, hasLength(2));
      final (first, retried) = (repository.reports.first, repository.reports.last);
      expect(retried.target, first.target);
      expect(retried.reason, first.reason);
      expect(retried.note, first.note);
      expect(state().outcome, ReportOutcome.reported);
      expect(state().errorMessage, isNull);
    });
  });
}
