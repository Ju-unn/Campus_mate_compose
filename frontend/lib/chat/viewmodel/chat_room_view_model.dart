import 'dart:async';

import 'package:campus_mate/chat/model/chat_errors.dart';
import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 방 하나당 하나. 화면을 닫으면 자동으로 버려지고 그때 실시간 구독도 함께 끊긴다.
final chatRoomViewModelProvider =
    NotifierProvider.autoDispose.family<ChatRoomViewModel, ChatRoomUiState, String>(
  ChatRoomViewModel.new,
);

/// 채팅방(화면 14)의 흐름. 게이트 수락·나가기도 여기서 맡는다 —
/// 게이트 전용 ViewModel 을 따로 두면 같은 방 상태를 두 벌 들고 있어야 한다.
class ChatRoomViewModel extends Notifier<ChatRoomUiState> {
  ChatRoomViewModel(this._matchId);

  final String _matchId;

  StreamSubscription<Message>? _subscription;

  /// 구독 세대. 재연결 때 옛 구독이 늦게 뱉는 줄·오류를 걸러 낸다 —
  /// 끊긴 채널은 닫는 데 시간이 걸려서 닫히기를 기다리지 않고 새로 건다.
  int _generation = 0;
  bool _alive = true;

  @override
  ChatRoomUiState build() {
    ref.onDispose(() {
      _alive = false;
      unawaited(_subscription?.cancel());
    });
    Future.microtask(_open);
    return const ChatRoomUiState();
  }

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  /// 들어올 때 하는 일. 읽음은 들어올 때와 나갈 때 한 번씩이다(ERD §4).
  Future<void> _open() async {
    // 방을 못 읽었으면 메시지도 읽지 않는다 — 머리말 없는 빈 방을 그리는 것보다 낫다.
    if (!await _loadRoom()) {
      return;
    }
    // 구독을 **첫 페이지 조회보다 먼저** 건다 — 그 사이에 들어온 줄이 영영 안 보이는 창을 없앤다.
    // 겹치는 줄은 id 가드와 아래의 이어 붙이기가 걸러 낸다(조각 5 리뷰 권고 4번).
    _subscribe();
    await _loadFirstPage();
    await markRead();
  }

  Future<bool> _loadRoom() async {
    final result = await _repository.fetchRoom(_matchId);
    if (!_alive) {
      return false;
    }
    state = result.when(
      onSuccess: (room) => state.copyWith(room: room),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: chatFailureMessage(failure)),
    );
    return state.room != null && state.errorMessage == null;
  }

  Future<void> _loadFirstPage() async {
    final result = await _repository.fetchMessages(_matchId);
    if (!_alive) {
      return;
    }
    state = result.when(
      onSuccess: (page) => state.copyWith(
        isLoading: false,
        // 조회하는 동안 구독이 붙여 둔 줄은 조회 결과에 없을 수 있다 — 덮어쓰지 않고 합친다.
        messages: _merge(state.messages, page.messages),
        hasMore: page.hasMore,
      ),
      onFailure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: chatFailureMessage(failure)),
    );
  }

  /// 들고 있던 줄과 새로 읽은 줄을 id 로 겹치지 않게 합쳐 시간순으로 세운다.
  /// 재연결 때는 위로 올려 읽어 둔 옛 줄이 남아 있어서 앞뒤로 그냥 붙이면 순서가 어긋난다 —
  /// 서버 커서와 같은 `(created_at, id)` 순으로 맞춘다.
  static List<Message> _merge(List<Message> held, List<Message> fetched) {
    final byId = {for (final message in [...held, ...fetched]) message.id: message};
    return byId.values.toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
  }

  /// 구독은 **화면이 살아 있는 동안만**. 끊는 것은 [build] 의 `onDispose` 가 한다.
  void _subscribe() {
    if (_subscription != null) {
      return;
    }
    final generation = ++_generation;
    _subscription = ref.read(messageStreamProvider).subscribe(_matchId).listen(
          (message) => generation == _generation ? _receive(message) : null,
          onError: (Object _) {
            if (generation == _generation) {
              _onDisconnected();
            }
          },
        );
  }

  /// 실시간 통로가 끊겼다(백로그 19). 혼자 조용히 다시 붙지 않는다 —
  /// 끊긴 동안 온 줄을 같이 가져와야 해서, 사용자가 누를 때 [reconnect] 한 번으로 묶는다.
  void _onDisconnected() {
    if (_alive) {
      state = state.copyWith(isDisconnected: true);
    }
  }

  /// 배너의 "다시 시도" 와 앱 복귀(백로그 18)가 같이 쓴다.
  /// 구독을 새로 걸고 **머리말과** 최근 50건을 다시 읽는다 — 끊긴 동안 들어온 줄은 구독으로는
  /// 영영 오지 않고, 그 사이에 상대가 나가거나 게이트가 통과됐을 수도 있다(머리말을 안 읽으면
  /// 입력창이 열린 채로 남아 409 가 나고 통과 카드도 안 뜬다).
  Future<void> reconnect() async {
    if (!_alive) {
      return;
    }
    // 닫히기를 기다리지 않는다 — 이미 끊긴 채널은 닫는 데 얼마가 걸릴지 모른다.
    // 늦게 오는 줄은 세대 검사가 버린다.
    unawaited(_subscription?.cancel());
    _subscription = null;
    state = state.copyWith(isDisconnected: false);
    _subscribe();
    await _loadRoom();
    await _loadFirstPage();
  }

  /// 내가 보낸 줄도 구독으로 한 번 더 돌아온다 — id 로 걸러 두 번 그리지 않는다.
  void _receive(Message message) {
    if (!_alive || state.messages.any((existing) => existing.id == message.id)) {
      return;
    }
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// 위로 올려 50건 더(결정 9). 커서는 화면에 있는 가장 오래된 줄이다.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) {
      return;
    }
    final oldest = state.messages.first;
    state = state.copyWith(isLoadingMore: true);
    final result = await _repository.fetchMessages(
      _matchId,
      before: oldest.createdAt,
      beforeId: oldest.id,
    );
    if (!_alive) {
      return;
    }
    state = result.when(
      onSuccess: (page) => state.copyWith(
        isLoadingMore: false,
        messages: [...page.messages, ...state.messages],
        hasMore: page.hasMore,
      ),
      onFailure: (failure) =>
          state.copyWith(isLoadingMore: false, errorMessage: chatFailureMessage(failure)),
    );
  }

  Future<void> send(String body) async {
    if (state.isSending) {
      return;
    }
    state = state.copyWith(isSending: true, errorMessage: null);
    final result = await _repository.sendMessage(_matchId, body);
    if (!_alive) {
      return;
    }
    state = state.copyWith(isSending: false);
    result.when<void>(
      // 서버는 INSERT 를 끝내고 닉네임 조회·푸시까지 한 뒤에 응답한다 — 구독 줄이 응답보다
      // 먼저 오는 것이 정상이다. 응답 줄도 같은 id 가드에 태워 두 번 그리지 않는다.
      onSuccess: (message) {
        if (message != null) {
          _receive(message);
        }
      },
      onFailure: (failure) {
        state = state.copyWith(errorMessage: chatFailureMessage(failure));
      },
    );
  }

  /// 방에 들어올 때와 나갈 때. 실패해도 화면에 문구를 띄우지 않는다 —
  /// 읽음 표시 하나가 안 찍힌 것으로 사용자가 할 수 있는 일이 없다.
  Future<void> markRead() async {
    await _repository.markRead(_matchId);
    if (_alive) {
      // 목록의 안 읽은 수와 하단 내비 뱃지를 같이 내린다.
      unawaited(ref.read(conversationsViewModelProvider.notifier).refresh());
    }
  }

  /// 나가기 = 게이트 거절(결정 11). 되돌릴 수 없다.
  Future<void> leave() async {
    final result = await _repository.leave(_matchId);
    if (!_alive) {
      return;
    }
    state = result.when(
      onSuccess: (_) => state.copyWith(hasLeft: true),
      // 이미 나갔다면 원하던 결과가 이미 났다 — 실패로 다루면 방에 갇힌다.
      onFailure: (failure) => isAlreadyLeft(failure)
          ? state.copyWith(hasLeft: true)
          : state.copyWith(errorMessage: chatFailureMessage(failure)),
    );
    if (state.hasLeft) {
      unawaited(ref.read(conversationsViewModelProvider.notifier).refresh());
    }
  }

  bool _acceptingTrust = false;

  /// 신뢰 확인 수락(결정 10). 매칭 순간부터 누를 수 있고 취소는 없다.
  ///
  /// 시트 버튼과 배너 버튼이 같은 길을 쓰고 응답이 오기 전에 한 번 더 눌릴 수 있다 —
  /// 보내는 중이면 두 번째 호출은 그냥 버린다.
  Future<void> acceptTrust() async {
    if (_acceptingTrust) {
      return;
    }
    _acceptingTrust = true;
    // 응답을 읽다 예외가 나도 플래그는 풀어야 한다 — 굳으면 그 방에서 다시 수락할 수 없다.
    try {
      final result = await _repository.acceptTrust(_matchId);
      if (!_alive) {
        return;
      }
      final failureMessage = result.when(
        onSuccess: (_) => null,
        // 이미 수락된 방이면 원하던 결과가 이미 났다 — 방만 다시 읽으면 된다.
        onFailure: (failure) =>
            isTrustAlreadyAnswered(failure) ? null : chatFailureMessage(failure),
      );
      if (failureMessage != null) {
        state = state.copyWith(errorMessage: failureMessage);
        return;
      }
      // 카카오톡 아이디·실사진은 방을 다시 읽어야 내려온다(통과 전에는 키 자체가 없다).
      await _loadRoom();
    } finally {
      _acceptingTrust = false;
    }
  }

  /// 시트를 스와이프로 닫았다. 강제가 아니라서 닫으면 14h 배너로 바뀐다.
  void dismissSheet() => state = state.copyWith(sheetDismissed: true);

  Future<void> retry() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    await _open();
  }
}
