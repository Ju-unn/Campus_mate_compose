import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/poll.dart';
import 'package:campus_mate/community/model/data/poll_comment.dart';

/// 17c 투표 상세 상태 — 글 하나와 그 댓글 목록. 피드 상태와 따로 들고 있어서 알림에서 바로 들어와도 열린다.
class PollDetailUiState {
  const PollDetailUiState({
    this.poll,
    this.isLoadingPoll = false,
    this.pollError,
    this.isVoting = false,
    this.comments = const [],
    this.hasMoreComments = false,
    this.isLoadingComments = true,
    this.isLoadingMoreComments = false,
    this.commentsError,
    this.moreError,
    this.isSending = false,
  });

  /// 피드에서 들어오면 피드 값으로 시작하고, 알림에서 들어오면 읽어 올 때까지 null.
  final Poll? poll;
  final bool isLoadingPoll;

  /// 글을 못 읽었을 때(글이 없거나 가려짐 404 · 연결 실패). 글이 이미 있으면 채우지 않는다.
  final Failure? pollError;
  final bool isVoting;

  /// 오래된 순. 내가 방금 보낸 댓글도 끝에 붙어 있다.
  final List<PollComment> comments;
  final bool hasMoreComments;
  final bool isLoadingComments;
  final bool isLoadingMoreComments;

  /// 댓글 첫 쪽을 못 읽었을 때만 채운다("다시 시도" 를 그린다).
  final Failure? commentsError;

  /// 이어 읽기(다음 10개)가 실패했을 때만 채운다. 목록 끝에 짧은 오류와 "다시 시도" 를 그린다 —
  /// 채워져 있는 동안은 스크롤로 자동 요청하지 않는다(실패한 요청을 끝없이 되풀이하지 않게).
  final Failure? moreError;
  final bool isSending;

  static const Object _keep = Object();

  /// 안 넘기면 그대로다. 오류 칸 셋은 **null 을 넘겨야** 지워진다(그래서 안 넘김과 null 을 가르는 [_keep]).
  PollDetailUiState copyWith({
    Poll? poll,
    bool? isLoadingPoll,
    Object? pollError = _keep,
    bool? isVoting,
    List<PollComment>? comments,
    bool? hasMoreComments,
    bool? isLoadingComments,
    bool? isLoadingMoreComments,
    Object? commentsError = _keep,
    Object? moreError = _keep,
    bool? isSending,
  }) {
    return PollDetailUiState(
      poll: poll ?? this.poll,
      isLoadingPoll: isLoadingPoll ?? this.isLoadingPoll,
      pollError: identical(pollError, _keep) ? this.pollError : pollError as Failure?,
      isVoting: isVoting ?? this.isVoting,
      comments: comments ?? this.comments,
      hasMoreComments: hasMoreComments ?? this.hasMoreComments,
      isLoadingComments: isLoadingComments ?? this.isLoadingComments,
      isLoadingMoreComments: isLoadingMoreComments ?? this.isLoadingMoreComments,
      commentsError: identical(commentsError, _keep) ? this.commentsError : commentsError as Failure?,
      moreError: identical(moreError, _keep) ? this.moreError : moreError as Failure?,
      isSending: isSending ?? this.isSending,
    );
  }
}
