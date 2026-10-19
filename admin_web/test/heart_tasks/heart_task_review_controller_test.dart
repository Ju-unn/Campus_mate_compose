import 'dart:async';

import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:campus_mate_admin/heart_tasks/heart_task_review_controller.dart';
import 'package:campus_mate_admin/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/heart_task_fakes.dart';

void main() {
  late FakeHeartTaskServer server;

  setUp(() {
    server = FakeHeartTaskServer([
      taskRow('e1'),
      taskRow('k1', task: 'kakao_share'),
      taskRow('e2'),
      taskRow('k2', task: 'kakao_share'),
    ]);
  });

  /// 화면 하나를 연 것처럼 provider 를 붙들고 첫 요청들(목록 → 첫 건)이 끝날 때까지 기다린다.
  Future<(ProviderContainer, HeartTaskReviewController)> open([String? initialId]) async {
    final container = ProviderContainer(
      overrides: [
        adminConfigProvider.overrideWithValue(completeConfig),
        adminAuthProvider.overrideWithValue(FakeAdminAuth(mfa: const MfaState(aal2: true, factorId: 'f'))),
        adminApiProvider.overrideWithValue(server.api()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(heartTaskReviewProvider(initialId), (_, _) {});
    await pumpEventQueue();
    return (container, container.read(heartTaskReviewProvider(initialId).notifier));
  }

  HeartTaskReviewState stateOf(ProviderContainer c, [String? initialId]) => c.read(heartTaskReviewProvider(initialId));
  List<String> ids(HeartTaskReviewState s) => [for (final i in s.items.value ?? const <HeartTaskItem>[]) i.id];

  test('처음 열면 대기 목록을 받고 첫 건을 골라 사진 · 지난 제출을 받아 온다', () async {
    final (c, _) = await open();
    final state = stateOf(c);

    expect(ids(state), ['e1', 'k1', 'e2', 'k2']);
    expect(state.selectedId, 'e1');
    expect(state.selected?.nickname, '닉네임A');
    expect(state.detail?.value?.photoUrl, startsWith('https://storage.test/e1.jpg'));
    expect(server.requests.map((r) => r.url.toString()), [
      'https://api.test/admin/heart-tasks',
      'https://api.test/admin/heart-tasks/e1',
    ]);
  });

  test('필터를 바꾸면 그 항목만 다시 받고 그 안의 첫 건을 고른다', () async {
    final (c, controller) = await open();

    controller.setFilter(HeartTaskKind.kakaoShare);
    expect(stateOf(c).items.isLoading, isTrue);
    await pumpEventQueue();

    expect(server.requests[2].url.queryParameters, {'task': 'kakao_share'});
    expect(stateOf(c).filter, HeartTaskKind.kakaoShare);
    expect(ids(stateOf(c)), ['k1', 'k2']);
    expect(stateOf(c).selectedId, 'k1');
  });

  test('승인하면 목록에서 빠지고 같은 필터 안의 다음 건을 고른다', () async {
    final (c, controller) = await open();
    controller.setFilter(HeartTaskKind.kakaoShare);
    await pumpEventQueue();

    expect(await controller.approve(), isTrue);
    await pumpEventQueue();

    expect(server.reviews, ['approve:k1']);
    expect(ids(stateOf(c)), ['k2']);
    expect(stateOf(c).selectedId, 'k2');
    expect(stateOf(c).detail?.value?.item.id, 'k2');
  });

  test('가운데 건을 처리하면 그 자리에 올라온 건, 맨 아래 건을 처리하면 맨 위 건을 고른다', () async {
    final (c, controller) = await open();

    await controller.select('k1');
    await controller.approve();
    await pumpEventQueue();
    expect(stateOf(c).selectedId, 'e2');

    await controller.select('k2');
    await controller.approve();
    await pumpEventQueue();
    expect(ids(stateOf(c)), ['e1', 'e2']);
    expect(stateOf(c).selectedId, 'e1');
  });

  test('마지막 남은 건을 처리하면 빈 목록 · 고른 건 없음', () async {
    server.pending.removeRange(1, 4);
    final (c, controller) = await open();

    await controller.approve();

    expect(stateOf(c).items.value, isEmpty);
    expect(stateOf(c).selectedId, isNull);
    expect(stateOf(c).detail, isNull);
  });

  test('반려는 고른 사유 하나를 보내고 다음 건으로 간다', () async {
    final (c, controller) = await open();

    expect(await controller.reject(HeartTaskRejectReason.reused), isTrue);
    await pumpEventQueue();

    expect(server.reviews, ['reject:e1:reused']);
    expect(stateOf(c).selectedId, 'k1');
  });

  test('409 면 "이미 처리됨" 상태가 되고 목록을 새로 받는다', () async {
    server.takenElsewhere.add('e1');
    final (c, controller) = await open();

    expect(await controller.approve(), isFalse);
    await pumpEventQueue();

    expect(stateOf(c).alreadyReviewed, isTrue);
    expect(server.listFetches, 2);
    expect(ids(stateOf(c)), ['k1', 'e2', 'k2']);
    expect(stateOf(c).selectedId, 'k1');
    expect(stateOf(c).busy, isNull);

    controller.dismissAlreadyReviewed();
    expect(stateOf(c).alreadyReviewed, isFalse);
  });

  test('처리 요청이 실패하면(500 · 연결 실패) 목록 · 선택은 그대로, 실패 표시만', () async {
    final (c, controller) = await open();

    for (final status in [500, 0]) {
      server.reviewFailure = status;
      expect(await controller.approve(), isFalse);

      expect(stateOf(c).reviewFailed, isTrue);
      expect(stateOf(c).busy, isNull);
      expect(ids(stateOf(c)), ['e1', 'k1', 'e2', 'k2']);
      expect(stateOf(c).selectedId, 'e1');
    }

    // 다시 시도하면 실패 표시를 내린다
    server.reviewFailure = null;
    expect(await controller.approve(), isTrue);
    expect(stateOf(c).reviewFailed, isFalse);
  });

  test('처리 중에 또 누르면 한 번만 보내고, 처리 중인 단추를 알린다', () async {
    final (c, controller) = await open();
    server.holdReview = Completer<void>();

    final first = controller.approve();
    await pumpEventQueue();
    expect(stateOf(c).busy, ReviewAction.approve);
    expect(await controller.reject(HeartTaskRejectReason.reused), isFalse);
    server.holdReview!.complete();
    await first;

    expect(server.reviews, ['approve:e1']);
  });

  test('사진 · 지난 제출을 다 받기 전에는 승인 · 반려를 보내지 않는다', () async {
    final (c, controller) = await open();
    server.holdDetail = Completer<void>();

    unawaited(controller.select('k1'));
    await pumpEventQueue();
    expect(stateOf(c).detail?.isLoading, isTrue);
    expect(await controller.approve(), isFalse);
    server.holdDetail!.complete();
    await pumpEventQueue();

    expect(server.reviews, isEmpty);
  });

  test('photo error refetches the item — 사진 오류면 그 건만 다시 받고, 다시 받은 주소도 깨지면 더 받지 않는다', () async {
    final (c, controller) = await open();
    final firstUrl = stateOf(c).detail!.value!.photoUrl;

    controller.photoFailed('e1');
    await pumpEventQueue();
    expect(server.detailFetches('e1'), 2);
    expect(server.listFetches, 1);
    expect(stateOf(c).detail!.value!.photoUrl, isNot(firstUrl));

    controller.photoFailed('e1');
    await pumpEventQueue();
    expect(server.detailFetches('e1'), 2, reason: '무한 반복 막기');

    // 사람이 그 줄을 다시 누르면 새로 받고, 그 뒤 오류는 한 번 더 다시 받을 수 있다
    await controller.select('e1');
    controller.photoFailed('e1');
    await pumpEventQueue();
    expect(server.detailFetches('e1'), 4);
  });

  test('다른 건을 고른 뒤 늦게 온 사진 오류는 무시한다', () async {
    final (_, controller) = await open();
    await controller.select('k1');

    controller.photoFailed('e1');
    await pumpEventQueue();

    expect(server.detailFetches('e1'), 1);
  });

  test('디스코드 링크(/heart-tasks/{id})로 열면 그 건을 고른다', () async {
    final (c, _) = await open('e2');

    expect(stateOf(c, 'e2').selectedId, 'e2');
    expect(server.detailFetches('e1'), 0);
  });

  test('링크로 연 건이 이미 처리됐으면 "이미 처리됨" 상태 + 목록의 첫 건', () async {
    server.others['done'] = {...taskRow('done'), 'status': 'approved'};
    final (c, _) = await open('done');
    await pumpEventQueue();

    expect(stateOf(c, 'done').alreadyReviewed, isTrue);
    expect(stateOf(c, 'done').selectedId, 'e1');
  });

  test('목록 밖(51번째 이후)의 대기 건을 링크로 열면 그 건을 보여 준다', () async {
    server.others['far'] = taskRow('far', nickname: '먼닉네임');
    final (c, _) = await open('far');

    expect(stateOf(c, 'far').selectedId, 'far');
    expect(stateOf(c, 'far').selected?.nickname, '먼닉네임');
    expect(stateOf(c, 'far').alreadyReviewed, isFalse);
  });

  test('없는 번호(404 · 422)로 열면 오류 없이 목록의 첫 건', () async {
    final (c, _) = await open('nope');
    await pumpEventQueue();

    expect(stateOf(c, 'nope').selectedId, 'e1');
    expect(stateOf(c, 'nope').detail?.hasError, isFalse);
  });

  test('목록을 못 받으면 오류 상태, 다시 시도하면 받는다', () async {
    server.listFailure = 0;
    final (c, controller) = await open();
    expect(stateOf(c).items.hasError, isTrue);

    server.listFailure = null;
    controller.retryList();
    await pumpEventQueue();

    expect(ids(stateOf(c)), ['e1', 'k1', 'e2', 'k2']);
  });

  test('링크 번호가 제출 번호 꼴이 아니면(..%2Fme → ../me) 그 번호로는 요청하지 않고 목록의 첫 건', () async {
    final (c, _) = await open('../me');
    await pumpEventQueue();

    expect(server.requests.map((r) => r.url.path), ['/admin/heart-tasks', '/admin/heart-tasks/e1']);
    expect(stateOf(c, '../me').selectedId, 'e1');
  });

  test('처리 중에 필터를 바꾸면 처리 결과가 새로 받는 목록을 덮지 않는다', () async {
    final (c, controller) = await open();
    server.holdReview = Completer<void>();
    final review = controller.approve();
    await pumpEventQueue();
    server.holdList = Completer<void>();
    controller.setFilter(HeartTaskKind.kakaoShare);

    server.holdReview!.complete();
    expect(await review, isTrue);
    expect(stateOf(c).items.isLoading, isTrue, reason: '옛 목록(빈 목록)으로 덮지 않는다');
    expect(stateOf(c).busy, isNull);

    server.holdList!.complete();
    await pumpEventQueue();
    expect(ids(stateOf(c)), ['k1', 'k2']);
    expect(stateOf(c).selectedId, 'k1');
  });

  test('처리 중에 다른 줄을 고르면 그 줄을 지키고 처리한 줄만 목록에서 뺀다', () async {
    final (c, controller) = await open();
    server.holdReview = Completer<void>();
    final review = controller.approve();
    await pumpEventQueue();
    await controller.select('k2');

    server.holdReview!.complete();
    expect(await review, isTrue);
    await pumpEventQueue();

    expect(stateOf(c).selectedId, 'k2');
    expect(ids(stateOf(c)), ['k1', 'e2', 'k2']);
    expect(stateOf(c).busy, isNull);
  });

  test('한 건을 못 받으면 그 칸만 오류, 다시 시도하면 받는다', () async {
    server.detailFailure = 500;
    final (c, controller) = await open();
    expect(stateOf(c).detail?.hasError, isTrue);
    expect(stateOf(c).selectedId, 'e1');

    server.detailFailure = null;
    controller.retryDetail();
    await pumpEventQueue();

    expect(stateOf(c).detail?.value?.item.id, 'e1');
  });

  test('401 · 403(관리자 해제 · 2단계 풀림)이면 관문을 다시 판정한다', () async {
    server.listFailure = 403;
    await open();
    await pumpEventQueue();

    expect(server.requests.where((r) => r.url.path == '/admin/me'), isNotEmpty);
  });
}
