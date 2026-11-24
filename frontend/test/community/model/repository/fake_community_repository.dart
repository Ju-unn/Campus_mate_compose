import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/community/model/data/community_category.dart';
import 'package:campus_mate/community/model/data/community_feed_tab.dart';
import 'package:campus_mate/community/model/data/community_item.dart';
import 'package:campus_mate/community/model/data/feed_page.dart';
import 'package:campus_mate/community/model/data/notice.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';
import 'package:campus_mate/community/model/repository/community_repository.dart';

Poll pollFixture({
  String id = 'p1',
  String question = '첫 데이트 더치페이',
  String optionA = defaultOptionA,
  String optionB = defaultOptionB,
  DateTime? createdAt,
  int aCount = 5,
  int bCount = 3,
  PollChoice? myChoice,
  bool isMine = false,
  int commentCount = 0,
}) =>
    Poll(
      id: id,
      question: question,
      optionA: optionA,
      optionB: optionB,
      createdAt: createdAt ?? DateTime(2026, 9, 27, 14),
      aCount: aCount,
      bCount: bCount,
      myChoice: myChoice,
      isMine: isMine,
      commentCount: commentCount,
    );

/// 피드 · 상세가 받는 투표 줄. 투표 칸은 [pollFixture] 와 같다.
CommunityItem itemFixture({
  String id = 'p1',
  String question = '첫 데이트 더치페이',
  String optionA = defaultOptionA,
  String optionB = defaultOptionB,
  DateTime? createdAt,
  int aCount = 5,
  int bCount = 3,
  PollChoice? myChoice,
  bool isMine = false,
  int commentCount = 0,
  CommunityCategory category = CommunityCategory.free,
}) =>
    CommunityItem.ofPoll(
      pollFixture(
        id: id,
        question: question,
        optionA: optionA,
        optionB: optionB,
        createdAt: createdAt,
        aCount: aCount,
        bCount: bCount,
        myChoice: myChoice,
        isMine: isMine,
        commentCount: commentCount,
      ),
      category: category,
    );

/// 피드 · 상세가 받는 게시물 줄.
CommunityItem postFixture({
  String id = 't1',
  String text = '취업 준비 다들 어떻게 해요?',
  DateTime? createdAt,
  bool isMine = false,
  int commentCount = 0,
  CommunityCategory category = CommunityCategory.career,
}) =>
    CommunityItem.post(
      id: id,
      category: category,
      text: text,
      createdAt: createdAt ?? DateTime(2026, 11, 24, 14),
      isMine: isMine,
      commentCount: commentCount,
    );

/// 공지 한 줄(할 일 21). 제목 · 본문은 지어낸 값이다.
Notice noticeFixture({
  String id = 'n1',
  String title = '업데이트 안내',
  String text = '이번 업데이트에서 바뀐 점이에요.',
  String? imageUrl,
  DateTime? createdAt,
  bool isNew = false,
  int commentCount = 0,
}) =>
    Notice(
      id: id,
      title: title,
      text: text,
      imageUrl: imageUrl,
      createdAt: createdAt ?? DateTime(2026, 11, 24, 9),
      isNew: isNew,
      commentCount: commentCount,
    );

PollComment commentFixture({
  String id = 'c1',
  String body = '저는 상관없어요',
  DateTime? createdAt,
  int? aliasNo = 1,
  bool isPostAuthor = false,
  bool isMine = false,
  bool canDelete = false,
}) =>
    PollComment(
      id: id,
      body: body,
      createdAt: createdAt ?? DateTime(2026, 9, 27, 13),
      aliasNo: aliasNo,
      isPostAuthor: isPostAuthor,
      isMine: isMine,
      canDelete: canDelete,
    );

/// 화면 · ViewModel 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeCommunityRepository implements CommunityRepository {
  Result<FeedPage<CommunityItem>> page = const Success(FeedPage(items: [], hasMore: false));

  /// 채워 두면 커서가 있는 요청(다음 쪽)에 이것을 돌려준다.
  Result<FeedPage<CommunityItem>>? nextPage;

  /// 탭별 첫 쪽. 없는 탭은 [page] 를 돌려준다.
  final Map<CommunityFeedTab, Result<FeedPage<CommunityItem>>> pageByTab = {};

  /// 채워 두면 목록 응답(첫 쪽 · 다음 쪽)이 이것이 끝날 때까지 멈춘다 — 늦게 도착한 응답 상황용.
  /// 부른 순간의 값을 잡으니, 요청 하나를 붙잡아 두고 비운 뒤 다음 요청은 바로 돌려줄 수 있다.
  Completer<void>? holdPage;

  /// 공지 첫 쪽. 커서가 있는 요청(더 보기)에는 [nextNoticePage] 를 돌려준다. 기본은 공지 없음(피드 띠 없음).
  Result<FeedPage<Notice>> noticePage = const Success(FeedPage(items: [], hasMore: false));
  Result<FeedPage<Notice>>? nextNoticePage;

  /// 채워 두면 공지 목록 응답이 이것이 끝날 때까지 멈춘다 — 늦게 도착한 응답 · 겹침 상황용.
  Completer<void>? holdNotices;
  final List<({DateTime? before, String? beforeId})> noticeRequests = [];

  /// 글 하나 읽기(`fetchItem`) 결과. 비워 두면 404.
  Result<CommunityItem>? item;

  /// 댓글 첫 쪽. 커서가 있는 요청(더 보기)에는 [nextCommentPage] 를 돌려준다.
  Result<FeedPage<PollComment>> commentPage = const Success(FeedPage(items: [], hasMore: false));
  Result<FeedPage<PollComment>>? nextCommentPage;
  Result<PollComment>? addCommentResult;
  Result<void> deleteCommentResult = const Success(null);

  /// 채워 두면 댓글 보내기 응답이 이것이 끝날 때까지 멈춘다 — 보내는 중 상태용.
  Completer<void>? holdAddComment;

  /// 채워 두면 이어 읽기(커서가 있는 요청)가 이것이 끝날 때까지 멈춘다 — 끝 로딩 표시 · 겹침 방지 확인용.
  Completer<void>? holdMoreComments;

  /// 채워 두면 댓글 첫 쪽(커서 없는 요청)이 이것이 끝날 때까지 멈춘다 — 새로 고침 중 상태용. 끝내기 전에 넣은 [commentPage] 를 돌려준다.
  Completer<void>? holdFirstComments;

  /// 커서는 시험이 읽기 쉽게 시각 · id 로 풀어 적는다.
  final List<({String itemId, DateTime? after, String? afterId})> commentRequests = [];
  final List<({String itemId, String body})> addedComments = [];
  final List<String> deletedComments = [];
  Result<void> createResult = const Success(null);
  Result<VoteOutcome>? voteResult;
  Result<void> deleteResult = const Success(null);

  /// 채워 두면 투표 응답이 이것이 끝날 때까지 멈춘다 — 누르는 도중 한 번 더 누르는 상황용.
  Completer<void>? holdVote;

  /// 채워 두면 글 하나 다시 읽기가 이것이 끝날 때까지 멈춘다 — 다시 읽는 도중 버려지는 상황용.
  Completer<void>? holdItem;

  /// 채워 두면 지우기 응답이 이것이 끝날 때까지 멈춘다 — 삭제 중(15d-2 `EIEFb`) 상태용.
  Completer<void>? holdDelete;

  /// 채워 두면 올리기(투표 · 게시물) 응답이 이것이 끝날 때까지 멈춘다 — 올리는 중(17b `UqasS`) 상태용.
  Completer<void>? holdCreate;

  final List<({CommunityFeedTab tab, DateTime? before, String? beforeId})> pageRequests = [];
  final List<({CommunityCategory category, String question, String optionA, String optionB})> created = [];
  final List<({CommunityCategory category, String body})> createdPosts = [];
  final List<({String pollId, PollChoice choice})> votes = [];
  final List<String> fetchedItemIds = [];
  final List<String> deleted = [];

  @override
  Future<Result<FeedPage<CommunityItem>>> fetchFeed({
    CommunityFeedTab tab = CommunityFeedTab.all,
    PageCursor? before,
  }) async {
    pageRequests.add((tab: tab, before: before?.createdAt, beforeId: before?.id));
    if (holdPage case final hold?) await hold.future;
    return before == null ? (pageByTab[tab] ?? page) : (nextPage ?? page);
  }

  @override
  Future<Result<CommunityItem>> fetchItem(String itemId) async {
    fetchedItemIds.add(itemId);
    await holdItem?.future;
    return item ?? const FailureResult(NotFoundFailure());
  }

  @override
  Future<Result<FeedPage<Notice>>> fetchNotices({PageCursor? before}) async {
    noticeRequests.add((before: before?.createdAt, beforeId: before?.id));
    if (holdNotices case final hold?) await hold.future;
    return before == null ? noticePage : (nextNoticePage ?? noticePage);
  }

  @override
  Future<Result<void>> createPoll({
    required CommunityCategory category,
    required String question,
    required String optionA,
    required String optionB,
  }) async {
    created.add((category: category, question: question, optionA: optionA, optionB: optionB));
    await holdCreate?.future;
    return createResult;
  }

  @override
  Future<Result<void>> createPost({required CommunityCategory category, required String body}) async {
    createdPosts.add((category: category, body: body));
    await holdCreate?.future;
    return createResult;
  }

  @override
  Future<Result<VoteOutcome>> vote(String pollId, PollChoice choice) async {
    votes.add((pollId: pollId, choice: choice));
    await holdVote?.future;
    return voteResult!;
  }

  @override
  Future<Result<void>> deleteItem(String itemId) async {
    deleted.add(itemId);
    await holdDelete?.future;
    return deleteResult;
  }

  @override
  Future<Result<FeedPage<PollComment>>> fetchComments(String itemId, {PageCursor? after}) async {
    commentRequests.add((itemId: itemId, after: after?.createdAt, afterId: after?.id));
    if (after != null) await holdMoreComments?.future;
    if (holdFirstComments case final hold? when after == null) await hold.future;
    return after == null ? commentPage : (nextCommentPage ?? commentPage);
  }

  @override
  Future<Result<PollComment>> addComment(String itemId, String body) async {
    addedComments.add((itemId: itemId, body: body));
    await holdAddComment?.future;
    return addCommentResult!;
  }

  @override
  Future<Result<void>> deleteComment(String commentId) async {
    deletedComments.add(commentId);
    return deleteCommentResult;
  }
}
