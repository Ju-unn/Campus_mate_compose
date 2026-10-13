import 'dart:async';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_view_model.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:campus_mate/matching/viewmodel/sent_requests_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 구독이 거부되거나 끊긴 뒤 처음 다시 시도할 때까지. 실패가 이어지면 두 배씩 [userChannelRetryMax] 까지 는다.
const Duration userChannelRetryFirst = Duration(seconds: 2);

/// 다시 시도 간격의 상한. 운영 DB 에 받기 정책이 없으면 입장이 계속 거부된다 — 그동안 사람마다 5분에 한 번이면 가볍다.
const Duration userChannelRetryMax = Duration(minutes: 5);

/// 상태 = 사용자 채널이 **실제로 붙었나(SUBSCRIBED)**. 목록 · 방 폴링이 이 값으로 빠르기(3초 · 2초)와 느리기(30초)를 고른다.
final userChannelProvider = NotifierProvider<UserChannel, bool>(UserChannel.new);

/// 로그인 · 관문을 통과한 사람의 우편함 채널 `user:<내 id>` 하나를, **앱이 앞에 있는 동안만** 듣는다(채팅 실시간 전환 설계안 A).
/// 켜고 끄는 때는 앱 루트(`main.dart`)가 정한다 — 앞으로 오면 [start], 뒤로 가면 [stop]. 로그아웃하면 SessionScope 가
/// 컨테이너째 버리고 그때 [build] 의 정리가 채널과 재시도를 닫는다.
///
/// 이벤트는 빨리 보여 주는 용도다 — 값의 기준은 늘 서버 API 다. 그래서 붙을 때마다(처음 · 다시) 목록을 한 번 읽어
/// 끊긴 동안 놓친 이벤트를 메우고, 읽는 중이면 각 뷰모델의 합치기 가드가 앱 복귀 읽기(`refreshOnResume`)와 겹침을 막는다.
class UserChannel extends Notifier<bool> {
  String? _profileId;
  StreamSubscription<UserEvent>? _subscription;
  Timer? _retry;
  Duration _retryDelay = userChannelRetryFirst;

  /// 구독 세대. 닫은 옛 구독이 늦게 뱉는 이벤트 · 신호를 걸러 낸다.
  int _generation = 0;

  @override
  bool build() {
    ref.onDispose(_close);
    return false;
  }

  /// 앱이 앞에 있고 로그인 · 관문을 통과했다. 이미 열려 있거나 다시 시도를 기다리는 중이면 아무것도 하지 않는다 —
  /// 관문 · 세션 알림이 여러 번 와도 채널은 하나이고, 기다리는 간격을 건너뛰어 폭주하지 않는다.
  void start(String profileId) {
    if (profileId == _profileId && (_subscription != null || _retry != null)) {
      return;
    }
    if (profileId != _profileId) {
      _retryDelay = userChannelRetryFirst;
    }
    stop();
    _profileId = profileId;
    _subscribe();
  }

  /// 앱이 뒤로 갔거나 로그아웃했다. 기다리던 재시도도 멈춘다 — 늘어난 간격은 남겨 두어 다음 복귀가 한 번만 바로 시도한다.
  void stop() {
    _close();
    // 이미 끊긴 상태면 건드리지 않는다 — 앱 루트가 위젯을 만드는 중(initState)에도 부르는데, 그때 상태를 바꾸면 Riverpod 이 막는다.
    if (state) {
      state = false;
    }
  }

  void _close() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _subscribe() {
    final generation = ++_generation;
    bool current() => generation == _generation;
    _subscription = ref
        .read(userEventStreamProvider)
        .subscribe(_profileId!, onSubscribed: () => current() ? _onLive() : null)
        .listen(
          (event) => current() ? _dispatch(event) : null,
          onError: (Object _) => current() ? _onDropped() : null,
        );
  }

  void _onLive() {
    _retryDelay = userChannelRetryFirst;
    state = true;
    _catchUp();
  }

  /// 입장 거부(정책 없음) · 끊김 · 서버가 닫음. 조용히 연결 안 됨으로 두고(폴링이 빨라진다) 채널을 닫은 뒤 간격을 두고 다시 연다.
  void _onDropped() {
    _close();
    state = false;
    _retry = Timer(_retryDelay, () {
      _retry = null;
      _subscribe();
    });
    final doubled = _retryDelay * 2;
    _retryDelay = doubled > userChannelRetryMax ? userChannelRetryMax : doubled;
  }

  /// 방 뷰모델이 살아 있는 동안 자기를 건다 — 그 방의 `read` · `message` 를 이 방에 바로 넘긴다.
  /// 이쪽에서 방 provider 를 찾지 않는 까닭: 방이 이 채널의 상태를 듣고 있어 거꾸로 읽으면 순환 의존(Riverpod 오류)이다.
  void attachRoom(String matchId, ChatRoomViewModel room) => _rooms[matchId] = room;

  /// 그 방 뷰모델이 버려질 때. 같은 방이 새로 걸렸으면(다시 만들어진 뷰모델) 그것은 남긴다.
  void detachRoom(String matchId, ChatRoomViewModel room) {
    if (identical(_rooms[matchId], room)) {
      _rooms.remove(matchId);
    }
  }

  /// 지금 화면에 살아 있는 방들. 없는 방은 새로 만들지 않는다 — 만들면 그 방을 열어 읽기 시작한다.
  final Map<String, ChatRoomViewModel> _rooms = {};

  void _dispatch(UserEvent event) {
    switch (event) {
      case MessageEvent():
        _onMessage(event);
      case ReadEvent():
        _rooms[event.matchId]?.receivePartnerRead(event);
      case RoomChangedEvent():
        _catchUp();
    }
  }

  /// 열린 방이 있으면 방에 먼저 붙이고(방 채널과 겹치면 id 로 걸러진다), 사용자가 그 방을 보고 있으면 목록의 안 읽은 수는 올리지 않는다.
  void _onMessage(MessageEvent event) {
    final seen = _rooms[event.matchId]?.receiveFromUserChannel(event.message) ?? false;
    ref.read(conversationsViewModelProvider.notifier).applyMessage(event, myId: _profileId!, seen: seen);
  }

  /// 새 방 · 닫힌 방 · 놓친 이벤트 — 대화 · 받은 신청 · 보낸 신청을 조용히 다시 읽는다(푸시 'match' 와 같은 셋).
  /// 대화 목록은 읽는 중이면 끝난 뒤 한 번 더 읽는다([ConversationsViewModel.catchUp]). 두 신청 목록은 읽는 중이면 합친다 —
  /// 새 매칭은 푸시(match)도 함께 와서 그쪽이 다시 읽는다.
  void _catchUp() {
    ref.read(conversationsViewModelProvider.notifier).catchUp();
    unawaited(ref.read(acceptancesViewModelProvider.notifier).refresh(quiet: true));
    unawaited(ref.read(sentRequestsViewModelProvider.notifier).refresh(quiet: true));
  }
}
