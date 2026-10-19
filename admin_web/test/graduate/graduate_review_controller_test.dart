import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:campus_mate_admin/graduate/graduate_review_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/graduate_fakes.dart';

void main() {
  late FakeGraduateServer server;

  setUp(() {
    server = FakeGraduateServer([graduateRow('g1'), graduateRow('g2'), graduateRow('g3', attemptNo: 2)]);
  });

  Future<(ProviderContainer, GraduateReviewController)> open([String? initialId]) async {
    final container = ProviderContainer(
      overrides: [
        adminConfigProvider.overrideWithValue(completeConfig),
        adminAuthProvider.overrideWithValue(FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f'))),
        adminApiProvider.overrideWithValue(server.api()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(graduateReviewProvider(initialId), (_, _) {});
    await pumpEventQueue();
    return (container, container.read(graduateReviewProvider(initialId).notifier));
  }

  GraduateReviewState stateOf(ProviderContainer c, [String? initialId]) => c.read(graduateReviewProvider(initialId));
  List<String> ids(GraduateReviewState s) => [for (final i in s.items.value ?? const <GraduateItem>[]) i.id];

  test('처음 열면 대기 목록과 학교 목록을 받고 첫 건을 골라 한 건을 받아 온다', () async {
    final (c, _) = await open();
    final state = stateOf(c);

    expect(ids(state), ['g1', 'g2', 'g3']);
    expect(state.selectedId, 'g1');
    expect(state.detail?.value?.photoUrl, startsWith('https://storage.test/g1.jpg'));
    expect(state.universities.value?.map((u) => u.name), ['고려대학교', '서울대학교', '연세대학교'], reason: '이름순');
    expect(server.requests.map((r) => r.url.path), containsAll(['/admin/graduate-requests', '/admin/graduate-requests/g1', '/admin/universities']));
    expect(server.requests.firstWhere((r) => r.url.path == '/admin/universities').url.queryParameters, {'include_empty': 'true'});
  });

  test('글자 인식이 읽은 번호를 입력 칸에 미리 채우고, 제안 학교를 미리 고른다', () async {
    final (c, _) = await open();
    final state = stateOf(c);

    expect(state.documentNumber, 'A12B-3456-78CD');
    expect(state.studentNumber, '');
    expect(state.universityId, 'u-snu');
    expect(state.universityChosenByAdmin, isFalse, reason: '미리 채운 것이라 사람이 확인하는 값');
  });

  test('못 읽은 건은 번호도 학교도 비어 있다', () async {
    server.detailOverrides['g1'] = {
      'ocr': {'state': 'nothing_found', 'document_number': null, 'school_text': null, 'suggested_university_ids': <Object?>[]},
    };
    final (c, _) = await open();

    expect(stateOf(c).documentNumber, '');
    expect(stateOf(c).universityId, isNull);
    expect(stateOf(c).canApprove, isFalse);
  });

  test('관리자가 고른 학교가 제안보다 앞선다', () async {
    final (c, controller) = await open();

    controller.setUniversity('u-yonsei');

    expect(stateOf(c).universityId, 'u-yonsei');
    expect(stateOf(c).universityChosenByAdmin, isTrue);
  });

  test('승인 가능 조건: 학교 · 번호(정규화 4~40자) · 학번은 비었거나 올바를 때', () async {
    final (c, controller) = await open();
    expect(stateOf(c).canApprove, isTrue);

    controller.setDocumentNumber('AB1');
    expect(stateOf(c).canApprove, isFalse, reason: '3자');
    controller.setDocumentNumber('  ');
    expect(stateOf(c).canApprove, isFalse, reason: '비어 있으면 승인 불가(D9)');
    controller.setDocumentNumber('가나다라마');
    expect(stateOf(c).canApprove, isFalse, reason: '한글은 OCR 오인');
    controller.setDocumentNumber('a1-b2 c3');
    expect(stateOf(c).canApprove, isTrue);

    controller.setStudentNumber('학번');
    expect(stateOf(c).canApprove, isFalse);
    controller.setStudentNumber('2021-0001');
    expect(stateOf(c).canApprove, isTrue);
  });

  test('승인: 본문에 고른 학교 · 입력한 번호 · 학번이 가고, 목록에서 빠지며 다음 건을 고른다', () async {
    final (c, controller) = await open();
    controller.setDocumentNumber('Z9-8888');
    controller.setStudentNumber('2021-0001');

    expect(await controller.approve(), isTrue);
    await pumpEventQueue();

    expect(server.reviews, ['approve:g1']);
    expect(server.approvals.single, {'university_id': 'u-snu', 'document_number': 'Z9-8888', 'student_number': '2021-0001'});
    expect(ids(stateOf(c)), ['g2', 'g3']);
    expect(stateOf(c).selectedId, 'g2');
  });

  test('승인하면 입력한 번호 · 학번을 비우고, 다음 건에는 그 건의 글자 인식 값이 들어간다', () async {
    server.detailOverrides['g2'] = {
      'ocr': {'state': 'read', 'document_number': 'NEXT-5555', 'school_text': '연세대학교', 'suggested_university_ids': ['u-yonsei']},
    };
    final (c, controller) = await open();
    controller.setDocumentNumber('SECRET-DOC-1');
    controller.setStudentNumber('SECRET-STU-1');

    await controller.approve();
    await pumpEventQueue();

    expect(stateOf(c).documentNumber, 'NEXT-5555');
    expect(stateOf(c).studentNumber, '');
    expect(stateOf(c).universityId, 'u-yonsei');
    expect(stateOf(c).toString(), isNot(contains('SECRET')));
  });

  test('마지막 건을 승인하면 입력이 모두 비고 고른 건이 없다', () async {
    server = FakeGraduateServer([graduateRow('g1')]);
    final (c, controller) = await open();
    controller.setStudentNumber('SECRET-STU-1');

    await controller.approve();
    await pumpEventQueue();

    expect(ids(stateOf(c)), isEmpty);
    expect(stateOf(c).selectedId, isNull);
    expect(stateOf(c).documentNumber, '');
    expect(stateOf(c).studentNumber, '');
  });

  test('반려: 사유 코드를 보내고 입력을 비우고 다음 건으로', () async {
    final (c, controller) = await open();
    controller.setStudentNumber('SECRET-STU-1');

    expect(await controller.reject(GraduateRejectReason.unverifiable), isTrue);
    await pumpEventQueue();

    expect(server.reviews, ['reject:g1:unverifiable']);
    expect(ids(stateOf(c)), ['g2', 'g3']);
    expect(stateOf(c).selectedId, 'g2');
    expect(stateOf(c).studentNumber, '');
  });

  test('승인 조건이 안 맞으면 요청을 보내지 않는다', () async {
    final (c, controller) = await open();
    controller.setDocumentNumber('');

    expect(await controller.approve(), isFalse);
    expect(server.reviews, isEmpty);
    expect(stateOf(c).busy, isNull);
  });

  test('처리 중에는 busy, 끝나면 풀린다 · 두 번째 요청은 보내지 않는다', () async {
    final (c, controller) = await open();
    server.holdReview = Completer<void>();

    final first = controller.approve();
    await pumpEventQueue();
    expect(stateOf(c).busy, ReviewAction.approve);
    expect(await controller.approve(), isFalse);
    expect(await controller.reject(GraduateRejectReason.unreadable), isFalse);

    server.holdReview!.complete();
    await first;
    expect(server.reviews, ['approve:g1']);
  });

  group('409 이유별 상태', () {
    for (final conflict in [
      GraduateConflict.alreadyVerified,
      GraduateConflict.accountWithdrawn,
      GraduateConflict.documentReused,
      GraduateConflict.studentReused,
      GraduateConflict.rejoinBlocked,
    ]) {
      test('${conflict.code}: 그 문구를 오류로 보이고 건 · 입력은 그대로 둔다', () async {
        server.conflicts['g1'] = conflict.code;
        final (c, controller) = await open();
        controller.setStudentNumber('2021-0001');

        expect(await controller.approve(), isFalse);

        final state = stateOf(c);
        expect(state.error, conflict.message);
        expect(state.alreadyReviewed, isFalse);
        expect(state.busy, isNull);
        expect(state.selectedId, 'g1');
        expect(ids(state), ['g1', 'g2', 'g3']);
        expect(state.studentNumber, '2021-0001', reason: '고쳐서 다시 낼 수 있게');
      });
    }

    test('already_reviewed: 대화상자 표시 + 목록을 새로 받아 그 건이 빠진다', () async {
      server.conflicts['g1'] = 'already_reviewed';
      final (c, controller) = await open();

      expect(await controller.approve(), isFalse);
      await pumpEventQueue();

      expect(stateOf(c).alreadyReviewed, isTrue);
      expect(stateOf(c).error, isNull);
      expect(ids(stateOf(c)), ['g2', 'g3']);

      controller.dismissAlreadyReviewed();
      expect(stateOf(c).alreadyReviewed, isFalse);
    });

    test('다른 건을 고르면 이전 오류 줄이 사라진다', () async {
      server.conflicts['g1'] = 'document_reused';
      final (c, controller) = await open();
      await controller.approve();
      expect(stateOf(c).error, isNotNull);

      await controller.select('g2');

      expect(stateOf(c).error, isNull);
    });
  });

  test('연결 실패 · 5xx · 422 는 일반 오류 문구', () async {
    final (c, controller) = await open();

    server.reviewFailure = 0;
    expect(await controller.approve(), isFalse);
    expect(stateOf(c).error, '처리하지 못했어요. 다시 시도해 주세요.');

    server.reviewFailure = 422;
    expect(await controller.approve(), isFalse);
    expect(stateOf(c).error, '입력한 값이 맞지 않아요. 문서확인번호 · 학번을 다시 확인해 주세요.');
    expect(stateOf(c).busy, isNull);
  });

  test('이미 결정된 건이 상세로 오면(다른 관리자가 처리) 알리고 목록을 새로 받는다', () async {
    server.others['g9'] = {...graduateRow('g9'), 'status': 'approved', 'photo_url': null, 'ocr': null, 'previous_school_email': null, 'warnings': <Object?>[], 'history': <Object?>[]};
    final (c, controller) = await open();

    await controller.select('g9');
    await pumpEventQueue();

    expect(stateOf(c).alreadyReviewed, isTrue);
  });

  test('목록 밖 · 틀린 번호로 연 링크는 오류 대신 첫 건', () async {
    final (c, _) = await open('nope-1');

    expect(stateOf(c, 'nope-1').selectedId, 'g1');
  });

  test('링크로 연 건을 처음에 고른다', () async {
    final (c, _) = await open('g2');

    expect(stateOf(c, 'g2').selectedId, 'g2');
  });

  test('목록 실패는 오류 상태, 다시 시도하면 받는다', () async {
    server.listFailure = 500;
    final (c, controller) = await open();
    expect(stateOf(c).items.hasError, isTrue);

    server.listFailure = null;
    controller.retryList();
    await pumpEventQueue();

    expect(ids(stateOf(c)), ['g1', 'g2', 'g3']);
  });

  test('학교 목록 실패는 따로 오류 상태 — 다시 받을 수 있다', () async {
    server.universitiesFailure = 500;
    final (c, controller) = await open();
    expect(stateOf(c).universities.hasError, isTrue);
    expect(stateOf(c).selectedId, 'g1', reason: '학교 목록 실패가 신청 화면을 막지 않는다');

    server.universitiesFailure = null;
    controller.retryUniversities();
    await pumpEventQueue();

    expect(stateOf(c).universities.value, hasLength(3));
  });

  test('한 건 실패는 그 건만 오류, 다시 시도하면 받는다', () async {
    server.detailFailure = 500;
    final (c, controller) = await open();
    expect(stateOf(c).detail?.hasError, isTrue);
    expect(ids(stateOf(c)), ['g1', 'g2', 'g3']);

    server.detailFailure = null;
    controller.retryDetail();
    await pumpEventQueue();

    expect(stateOf(c).detail?.value?.id, 'g1');
  });

  test('사진이 깨지면 그 건만 한 번 다시 받고, 입력해 둔 번호는 지우지 않는다', () async {
    server.brokenOnce.add('g1');
    final (c, controller) = await open();
    controller.setDocumentNumber('TYPED-1234');

    controller.photoFailed('g1');
    await pumpEventQueue();
    controller.photoFailed('g1'); // 두 번째는 받지 않는다
    await pumpEventQueue();

    expect(server.detailFetches('g1'), 2);
    expect(stateOf(c).documentNumber, 'TYPED-1234');
    expect(stateOf(c).detail?.value?.photoUrl, contains('v=2'));
  });

  test('같은 줄을 다시 눌러도 입력해 둔 번호는 지우지 않는다', () async {
    final (c, controller) = await open();
    controller.setDocumentNumber('TYPED-1234');

    await controller.select('g1');

    expect(stateOf(c).documentNumber, 'TYPED-1234');
  });

  test('다른 건으로 옮기면 입력이 그 건의 글자 인식 값으로 바뀐다(앞 건의 번호가 남지 않는다)', () async {
    final (c, controller) = await open();
    controller.setDocumentNumber('TYPED-1234');
    controller.setStudentNumber('SECRET-STU-1');

    await controller.select('g2');

    expect(stateOf(c).documentNumber, 'A12B-3456-78CD');
    expect(stateOf(c).studentNumber, '');
  });

  test('401 · 403(관리자 해제 · 2단계 풀림)이면 관문을 다시 판정한다', () async {
    server.listFailure = 403;
    await open();
    await pumpEventQueue();

    expect(server.requests.where((r) => r.url.path == '/admin/me'), isNotEmpty);
  });

  test('상태 toString 에는 입력 평문이 나오지 않는다', () async {
    final (c, controller) = await open();
    controller.setDocumentNumber('SECRET-DOC-1');
    controller.setStudentNumber('SECRET-STU-1');

    final text = stateOf(c).toString();

    expect(text, isNot(contains('SECRET')));
    expect(text, isNot(contains('A12B')), reason: '글자 인식 번호도 마찬가지');
  });
}
