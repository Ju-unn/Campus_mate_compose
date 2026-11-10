import 'package:campus_mate/billing/task/model/data/heart_task.dart';
import 'package:campus_mate/billing/task/view/heart_task_submit_screen.dart';
import 'package:campus_mate/core/analytics/analytics_values.dart';
import 'package:campus_mate/core/push/push_route.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('카드 도착 알림은 오늘 탭으로 간다', () {
    expect(PushRoute.resolve({'route': 'daily_card', 'card_id': 'c1'}), AppRoutes.today);
  });

  test('받은 수락 알림은 대화 목록으로 간다', () {
    expect(PushRoute.resolve({'route': 'acceptances', 'card_id': 'c1'}), AppRoutes.conversations);
  });

  test('매칭 성사 알림은 대화 목록으로 간다 — 방은 목록에서 골라 들어간다', () {
    expect(PushRoute.resolve({'route': 'match', 'match_id': 'm1'}), AppRoutes.conversations);
  });

  test('채팅 알림은 그 방으로 바로 간다', () {
    expect(PushRoute.resolve({'route': 'chat', 'match_id': 'm1'}), '/chat/m1');
  });

  test('방 id 가 없는 채팅 알림은 목록으로 보낸다', () {
    // 엉뚱한 방을 여는 것보다 목록이 낫다.
    expect(PushRoute.resolve({'route': 'chat'}), AppRoutes.conversations);
    expect(PushRoute.resolve({'route': 'chat', 'match_id': ''}), AppRoutes.conversations);
  });

  test('새 지인 리뷰 알림은 받은 리뷰(20c)로 간다', () {
    expect(PushRoute.resolve({'route': 'friend_reviews'}), AppRoutes.friendReviews);
  });

  test('추천 가입 알림은 홈 위에 그 친구의 리뷰 쓰기(20b)를 연다', () {
    expect(PushRoute.resolve({'route': 'friend_review_write', 'profile_id': 'p2'}), '/home/friend-reviews/write/p2');
  });

  test('누구에게 쓸지 모르는 리뷰 쓰기 알림은 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'friend_review_write'}), isNull);
    expect(PushRoute.resolve({'route': 'friend_review_write', 'profile_id': ''}), isNull);
  });

  // 11-10 O/X 글 새 댓글: 글쓴이에게 가는 푸시(data route poll + poll_id)는 그 글의 상세(17c)로 바로 간다.
  group('내 글의 새 댓글 알림', () {
    test('그 글의 상세로 간다', () {
      expect(PushRoute.resolve({'route': 'poll', 'poll_id': 'p1'}), '/community/polls/p1');
      expect(PushRoute.resolve({'route': 'poll', 'poll_id': 'p1'}), '${AppRoutes.communityPoll}/p1');
    });

    test('어느 글인지 모르면 아무 데도 보내지 않는다', () {
      expect(PushRoute.resolve({'route': 'poll'}), isNull);
      expect(PushRoute.resolve({'route': 'poll', 'poll_id': ''}), isNull);
    });

    test('사용 통계 종류는 poll', () {
      expect(PushRoute.typeOf({'route': 'poll', 'poll_id': 'p1'}), PushOpenType.poll);
      expect(PushOpenType.poll.wire, 'poll');
    });
  });

  // 10-17 학생증 제거: 알림함에 남은 옛 "학생증 결과" 줄(route verification)은 모르는 값처럼 아무 데도 보내지 않는다.
  test('옛 학생증 검토 결과 알림(verification)은 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'verification'}), isNull);
  });

  // 10-18 인증샷 결과 알림: 승인 → 18a, 반려 → 18b-2(사유 알림이 뜨는 다시 제출).
  group('인증샷 결과 알림', () {
    test('승인(heart_tasks)은 무료로 하트 모으기 18a 로 간다', () {
      expect(PushRoute.resolve({'route': 'heart_tasks', 'task': 'kakao_share'}), AppRoutes.heartTasks);
    });

    test('반려(heart_task_retry)는 사유를 실은 18b-2 로 간다 — 18a 줄을 눌렀을 때와 같은 경로', () {
      final path = PushRoute.resolve({'route': 'heart_task_retry', 'task': 'everytime_post', 'reason': 'date_missing'});

      expect(path, '/heart-tasks/submit/everytime_post?reason=date_missing');
      expect(path, heartTaskSubmitLocation(HeartTaskKind.everytimePost, HeartTaskRejectReason.dateMissing));
    });

    test('사유가 없거나 모르는 값이면 사유 알림 없는 18b 로 간다', () {
      for (final reason in <Object?>[null, 'blurry', '', 7]) {
        expect(
          PushRoute.resolve({'route': 'heart_task_retry', 'task': 'kakao_share', 'reason': reason}),
          '/heart-tasks/submit/kakao_share',
        );
      }
      expect(PushRoute.resolve({'route': 'heart_task_retry', 'task': 'kakao_share'}), '/heart-tasks/submit/kakao_share');
    });

    test('항목(task)이 없거나 인증샷 항목이 아니면 18a 로 보낸다 — 알 수 없는 값을 경로에 싣지 않는다', () {
      for (final task in <Object?>[null, '', 'poll_vote', '../x', 'everytime_post/../../me', 3]) {
        final path = PushRoute.resolve({'route': 'heart_task_retry', 'task': task, 'reason': 'reused'});

        expect(path, AppRoutes.heartTasks, reason: '$task');
      }
    });
  });

  test('모르는 route 는 아무 데도 보내지 않는다', () {
    expect(PushRoute.resolve({'route': 'sticker'}), isNull);
    expect(PushRoute.resolve(const {}), isNull);
  });

  test('졸업생 인증 결과 알림은 아무 데도 보내지 않는다 — 관문(AuthRedirect)이 화면을 옮긴다', () {
    expect(PushRoute.resolve({'route': 'graduate_verification', 'state': 'approved'}), isNull);
    expect(PushRoute.resolve({'route': 'graduate_verification', 'state': 'rejected', 'reason': 'unreadable'}), isNull);
  });

  // 사용 통계 push_open.type — 알고 있는 route 값만 그대로, 그 밖에는 other. data 의 다른 값은 보지 않는다.
  group('typeOf — 사용 통계 종류값', () {
    test('알고 있는 route 는 그대로 종류값이다', () {
      const known = {
        'daily_card': PushOpenType.dailyCard,
        'acceptances': PushOpenType.acceptances,
        'match': PushOpenType.match,
        'chat': PushOpenType.chat,
        'friend_reviews': PushOpenType.friendReviews,
        'friend_review_write': PushOpenType.friendReviewWrite,
        'heart_tasks': PushOpenType.heartTasks,
        'heart_task_retry': PushOpenType.heartTaskRetry,
      };
      for (final MapEntry(key: route, value: type) in known.entries) {
        expect(PushRoute.typeOf({'route': route}), type, reason: route);
      }
    });

    test('모르는 route · route 없음 · 문자열이 아닌 값은 other', () {
      expect(PushRoute.typeOf({'route': 'verification'}), PushOpenType.other);
      expect(PushRoute.typeOf({'route': '홍길동'}), PushOpenType.other);
      expect(PushRoute.typeOf({'route': 7}), PushOpenType.other);
      expect(PushRoute.typeOf(const {}), PushOpenType.other);
    });

    test('resolve 가 알아보는 route 는 모두 종류값이 있다 — 새 route 를 더하면 여기서 걸린다', () {
      const resolvable = [
        'daily_card',
        'acceptances',
        'match',
        'chat',
        'friend_reviews',
        'friend_review_write',
        'heart_tasks',
        'heart_task_retry',
      ];
      for (final route in resolvable) {
        expect(PushRoute.typeOf({'route': route}).wire, route);
      }
    });
  });
}
