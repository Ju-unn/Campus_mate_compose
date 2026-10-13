import 'dart:async';

import 'package:campus_mate/chat/model/chat_errors.dart';
import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/user_event_stream.dart';
import 'package:campus_mate/chat/viewmodel/chat_room_ui_state.dart';
import 'package:campus_mate/chat/viewmodel/conversations_view_model.dart';
import 'package:campus_mate/chat/viewmodel/user_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 방 하나당 하나. 화면을 닫으면 자동으로 버려지고 그때 실시간 구독도 함께 끊긴다.
final chatRoomViewModelProvider =
    NotifierProvider.autoDispose.family<ChatRoomViewModel, ChatRoomUiState, String>(
  ChatRoomViewModel.new,
);

/// 채팅방 화면이 게이트 단계(배너·시트)를 가를 때 쓰는 시계. 테스트가 갈아끼운다
/// (`verifyCodeNowProvider` 와 같은 방식) — 24시간 경계를 실제 시계 없이 넘기려고(백로그 22).
final chatRoomNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 방이 보이는 동안 상대가 내 줄을 읽었는지 묻는 주기(카톡식 '1', 사용자 결정 10-13, 같은 날 사용자 요청으로 5초 → 2초) —
/// 사용자 채널(`user:<내 id>`, 설계안 A)이 **안 붙었을 때**(정책 적용 전 입장 거부 · 끊김). 메시지 1건 조회라 가볍다.
const Duration partnerReadPollFast = Duration(seconds: 2);

/// 사용자 채널이 붙어 있을 때의 주기. 읽음은 `read` 이벤트로 바로 오고 이것은 이벤트 유실을 메우는 안전망이다.
const Duration partnerReadPollSlow = Duration(seconds: 30);

/// 방을 보는 동안 받은 상대 줄의 읽음을 묶는 간격. 첫 줄에 바로 찍고, 그 사이 온 줄은 끝에 한 번 더 찍는다.
const Duration markReadThrottle = Duration(seconds: 3);

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

  /// 방이 화면에 보이는가. 화면이 앱 생명주기와 덮인 화면으로 알려 준다([setVisible]).
  bool _visible = true;
  Timer? _partnerReadPoll;
  bool _checkingPartnerRead = false;
  Timer? _markReadWindow;

  /// 묶음 창이 열려 있거나 방이 안 보이는 동안 상대 줄이 와서, 다음 기회에 읽음을 찍어야 한다.
  bool _markReadOwed = false;

  @override
  ChatRoomUiState build() {
    ref.onDispose(() {
      _alive = false;
      _stopReadSync();
      unawaited(_subscription?.cancel());
    });
    // 사용자 채널이 붙거나 끊기면 상대 읽음 확인 간격을 바꾼다(붙음 30초 · 아니면 2초).
    ref.listen<bool>(userChannelProvider, (_, _) => _onUserChannelChanged());
    // 이 방에 온 `read` · `message` 이벤트를 채널이 바로 넘겨주게 건다. 버려질 때 뗀다(onDispose 안에서는 ref 를 못 쓴다).
    final channel = ref.read(userChannelProvider.notifier)..attachRoom(_matchId, this);
    ref.onDispose(() => channel.detachRoom(_matchId, this));
    Future.microtask(_open);
    return const ChatRoomUiState();
  }

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  /// 들어올 때 하는 일. 읽음은 들어올 때와 나갈 때 찍고(ERD §4), 방을 보는 동안 받은 상대 줄은
  /// [_markReadSoon] 이 묶어서 찍는다(카톡식 '1', 사용자 결정 10-13).
  Future<void> _open() async {
    // 방을 못 읽었으면 메시지도 읽지 않는다 — 머리말 없는 빈 방을 그리는 것보다 낫다.
    if (!await _loadRoom()) {
      return;
    }
    // 구독을 **첫 페이지 조회보다 먼저** 건다 — 그 사이에 들어온 줄이 영영 안 보이는 창을 없앤다.
    // 겹치는 줄은 id 가드와 아래의 이어 붙이기가 걸러 낸다(조각 5 리뷰 권고 4번).
    _subscribe();
    await _loadFirstPage();
    _refreshIfRoomChangedMeanwhile();
    await markRead();
    if (_alive && _visible) {
      _startPartnerReadPoll();
    }
  }

  /// 머리말을 읽은 직후 상대가 두 번째로 수락하거나 나가면 그 줄은 구독이 아니라 첫 페이지로 들어와
  /// [_receive] 를 타지 않는다. 첫 페이지를 합친 뒤([_open]·[reconnect]) 한 번 본다.
  /// 수락은 내가 이미 수락한 방일 때만 본다 — 아니면 상대 수락 줄로는 통과될 수 없다.
  void _refreshIfRoomChangedMeanwhile() {
    final room = state.room;
    if (room == null) {
      return;
    }
    final accepted = room.gate.accepted &&
        !room.gate.passed &&
        state.messages.any((message) => _isPartnerAccept(room, message));
    if (accepted || state.messages.any((message) => _isUnseenLeft(room, message))) {
      unawaited(_loadRoom(quiet: true));
    }
  }

  static bool _isPartnerAccept(ChatRoom room, Message message) =>
      message.kind == MessageKind.trustAccept && message.senderId == room.partner.profileId;

  /// 나감 줄은 상대만 남긴다(내가 나가면 방을 못 본다). 머리말이 아직 모르면 다시 읽어야 입력창이 잠긴다.
  static bool _isUnseenLeft(ChatRoom room, Message message) =>
      message.kind == MessageKind.left && !room.gate.partnerLeft;

  /// [quiet] 는 사용자가 누르지 않은 백그라운드 재조회다 — 실패해도 오류 줄을 띄우지 않고,
  /// 성공해도 떠 있던 오류 줄을 지우지 않는다(사용자가 할 수 있는 일이 없다).
  Future<bool> _loadRoom({bool quiet = false}) async {
    final result = await _repository.fetchRoom(_matchId);
    if (!_alive) {
      return false;
    }
    if (quiet) {
      result.when<void>(
        onSuccess: (room) => state = state.copyWith(
          room: room,
          partnerRead: state.partnerRead.later(room.partnerRead),
          errorMessage: state.errorMessage,
        ),
        onFailure: (_) {},
      );
      return state.room != null;
    }
    state = result.when(
      onSuccess: (room) =>
          state.copyWith(room: room, partnerRead: state.partnerRead.later(room.partnerRead)),
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
        partnerRead: state.partnerRead.later(page.partnerRead),
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

  /// 구독이 "글을 밀어 줄 준비가 됐을 수 있다" 고 알렸다(E-CHAT-67). 서버는 postgres_changes 복제를 join 성공 **뒤에**
  /// 비동기로 살려서, 첫 페이지를 읽은 뒤 ~ 복제가 살기 전에 들어온 줄은 첫 읽기도 구독도 못 받는다 — 첫 페이지를 한 번 더 읽어 합친다.
  /// **조용하다**: 로딩 · `hasMore`(이미 위로 읽어 둔 옛 줄) · 떠 있던 오류 줄을 건드리지 않고 실패해도 문구를 띄우지 않는다.
  /// 겹쳐 불려도(처음 붙음 · system 이벤트 · 첫 페이지 읽기) 합치기가 id 로 멱등이라 막지 않는다 —
  /// 진행 중이면 건너뛰는 가드는 오히려 먼저 시작한 읽기가 놓친 줄을 두 번째 신호가 데려오지 못하게 한다.
  Future<void> _catchUpAfterReady() async {
    if (!_alive) {
      return;
    }
    final result = await _repository.fetchMessages(_matchId);
    if (!_alive) {
      return;
    }
    result.when<void>(onSuccess: _mergeQuietly, onFailure: (_) {});
  }

  void _mergeQuietly(MessagePage page) {
    final held = state.messages.length;
    state = state.copyWith(
      messages: _merge(state.messages, page.messages),
      partnerRead: state.partnerRead.later(page.partnerRead),
      errorMessage: state.errorMessage,
    );
    _refreshIfRoomChangedMeanwhile();
    // 구독이 놓친 줄을 여기서 처음 봤다 — 상대 줄이면 읽음을 찍어야 상대 화면의 '1' 이 사라진다.
    if (state.messages.length > held) {
      _markReadSoon();
    }
  }

  /// 구독은 **화면이 살아 있는 동안만**. 끊는 것은 [build] 의 `onDispose` 가 한다.
  void _subscribe() {
    if (_subscription != null) {
      return;
    }
    final generation = ++_generation;
    _subscription = ref
        .read(messageStreamProvider)
        // 짧게 끊겼다가 통로가 스스로 다시 붙었다 — 배너의 "다시 시도" 와 같은 길로 놓친 줄을 데려온다(결함 A12).
        .subscribe(
          _matchId,
          onRejoined: () => generation == _generation ? unawaited(reconnect()) : null,
          // 서버가 글을 밀어 줄 준비가 됐을 수 있다(E-CHAT-67) — **reconnect 가 아니라** 조용한 한 번 더 읽기다.
          // 다시 구독하면 다시 붙음 → 다시 구독이 끝없이 돈다.
          onReady: () => generation == _generation ? unawaited(_catchUpAfterReady()) : null,
        )
        .listen(
          (message) => generation == _generation ? _receive(message) : null,
          onError: (Object _) {
            if (generation == _generation) {
              _onDisconnected();
            }
          },
        );
  }

  /// 실시간 통로가 끊겼다(백로그 19). 배너만 켠다 — 끊긴 동안 온 줄을 같이 가져와야 해서 [reconnect] 한 번으로
  /// 묶는다. 사용자가 "다시 시도" 를 누르거나, 통로가 스스로 다시 붙으면(결함 A12) 그 길을 탄다.
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
    _refreshIfRoomChangedMeanwhile();
    // 끊긴 동안 · 백그라운드에 있는 동안 온 상대 줄을 이제 본다.
    _markReadSoon();
  }

  /// 내가 보낸 줄도 구독으로 한 번 더 돌아온다 — id 로 걸러 두 번 그리지 않는다.
  /// 새 줄은 맨 뒤에 붙이지 않고 `(created_at, id)` 자리에 끼운다 — 내 응답은 서버가 닉네임 조회 · 푸시를 한 뒤에 오므로
  /// 그 사이 온 상대 줄보다 늦게 도착해도 DB 순서(서버 커서)와 같은 자리에 서야 두 화면의 순서가 같다.
  void _receive(Message message) {
    if (!_alive || state.messages.any((existing) => existing.id == message.id)) {
      return;
    }
    state = state.copyWith(messages: _merge(state.messages, [message]));
    final room = state.room;
    // 방을 보고 있는 동안 온 상대 줄 — 읽음을 찍어야 상대 화면의 내 '1' 이 사라진다.
    if (room != null && message.senderId == room.partner.profileId) {
      _markReadSoon();
    }
    // 상대가 두 번째로 수락해 통과되면 구독으로는 수락 줄만 온다 — 통과 카드·카카오톡 아이디·
    // 실사진은 머리말을 다시 읽어야 내려온다. 내 수락은 [acceptTrust] 가 응답 뒤에 이미 읽는다.
    // 상대가 나가도 구독으로는 나감 줄만 온다 — 머리말을 다시 읽어야 입력창이 안내로 바뀐다(결정 7 · 결함 A12).
    if (room != null &&
        (!room.gate.passed && _isPartnerAccept(room, message) || _isUnseenLeft(room, message))) {
      unawaited(_loadRoom(quiet: true));
    }
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

  /// 보냈으면 true — 입력 바가 실패 때 글을 되돌리는 데 쓴다.
  Future<bool> send(String body) async {
    if (state.isSending) {
      return false;
    }
    state = state.copyWith(isSending: true, errorMessage: null);
    final result = await _repository.sendMessage(_matchId, body);
    if (!_alive) {
      return false;
    }
    state = state.copyWith(isSending: false);
    return result.when(
      // 서버는 INSERT 를 끝내고 닉네임 조회·푸시까지 한 뒤에 응답한다 — 구독 줄이 응답보다
      // 먼저 오는 것이 정상이다. 응답 줄도 같은 id 가드에 태워 두 번 그리지 않는다.
      onSuccess: (message) {
        if (message != null) {
          _receive(message);
        }
        return true;
      },
      onFailure: (failure) {
        state = state.copyWith(errorMessage: chatFailureMessage(failure));
        return false;
      },
    );
  }

  /// 방에 들어올 때(목록 뱃지도 같이 내린다). 실패해도 화면에 문구를 띄우지 않는다 —
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

  /// 방이 화면에 보이는가 — 앱 복귀 · 덮었던 화면이 닫힘 = true, 백그라운드 · 다른 화면이 덮음 = false.
  /// 안 보이는 동안에는 상대 읽음을 묻지 않고 **읽음도 찍지 않는다** — 보지 않은 줄을 읽었다고 알리면 안 된다.
  /// 다시 보이면 바로 한 번 묻고 [partnerReadPollFast] · [partnerReadPollSlow] 주기를 이어 가며, 그사이 온 상대 줄의 읽음을 찍는다.
  void setVisible(bool visible) {
    if (visible == _visible) {
      return;
    }
    _visible = visible;
    if (!visible) {
      _stopReadSync();
      return;
    }
    _resumeReadSync();
  }

  void _resumeReadSync() {
    if (!_alive || state.room == null) {
      return;
    }
    unawaited(_checkPartnerRead());
    _startPartnerReadPoll();
    if (_markReadOwed) {
      _markReadSoon();
    }
  }

  void _stopReadSync() {
    _partnerReadPoll?.cancel();
    _partnerReadPoll = null;
    _markReadWindow?.cancel();
    _markReadWindow = null;
  }

  void _startPartnerReadPoll() {
    _partnerReadPoll?.cancel();
    final interval = ref.read(userChannelProvider) ? partnerReadPollSlow : partnerReadPollFast;
    _partnerReadPoll = Timer.periodic(interval, (_) => unawaited(_checkPartnerRead()));
  }

  /// 확인이 돌고 있을 때만(방이 보이고 열렸다) 새 간격으로 다시 걸고 바로 한 번 묻는다 — 끊긴 동안 놓친 `read` 를 메운다.
  void _onUserChannelChanged() {
    if (_partnerReadPoll == null) {
      return;
    }
    _startPartnerReadPoll();
    unawaited(_checkPartnerRead());
  }

  /// 사용자 채널로 온 상대의 읽음(설계안 A) — 폴링을 기다리지 않고 '1' 을 지운다. 늦게 읽은 값이 이긴다([PartnerRead.later]).
  /// 다른 방 · 상대가 아닌 사람의 읽음은 쓰지 않는다(서버는 상대 한 명에게만 쏘지만 내 읽음으로 '1' 을 지우면 거짓말이 된다).
  void receivePartnerRead(ReadEvent event) {
    final room = state.room;
    if (!_alive || event.matchId != _matchId || room == null || event.readerId != room.partner.profileId) {
      return;
    }
    _takePartnerRead(PartnerRead.known(event.readAt));
  }

  /// 사용자 채널로 온 이 방의 줄. 방 채널로도 오는 줄이라 id 로 걸러 한 번만 그린다 — 방 채널 복제가 늦을 때 먼저 보인다.
  /// 사용자가 지금 이 방을 보고 있으면 true 다 — 목록이 안 읽은 수를 올리지 않는다.
  bool receiveFromUserChannel(Message message) {
    _receive(message);
    return _alive && _visible;
  }

  /// 상대가 내 줄을 읽었는지 가볍게 묻는다(메시지 1건 조회). 메시지 목록은 건드리지 않는다.
  /// 안 읽은 내 줄이 없으면 묻지 않고(상대가 나간 방 · 옛 서버도 여기서 걸린다), 앞 확인이 끝나기 전에는
  /// 겹쳐 부르지 않는다. 실패는 조용히 넘긴다 — 다음 주기에 다시 묻는다.
  Future<void> _checkPartnerRead() async {
    if (_checkingPartnerRead || !state.messages.any(state.isUnreadByPartner)) {
      return;
    }
    _checkingPartnerRead = true;
    try {
      final result = await _repository.fetchPartnerRead(_matchId);
      if (_alive) {
        result.when<void>(onSuccess: _takePartnerRead, onFailure: (_) {});
      }
    } finally {
      _checkingPartnerRead = false;
    }
  }

  /// 떠 있던 오류 줄은 그대로 둔다 — 사용자가 누른 일이 아니다.
  void _takePartnerRead(PartnerRead read) => state =
      state.copyWith(partnerRead: state.partnerRead.later(read), errorMessage: state.errorMessage);

  /// 방을 보는 동안 받은 상대 줄을 읽음으로 찍는다 — 이게 있어야 상대 화면의 내 '1' 이 사라진다.
  /// 줄마다 부르지 않고 [markReadThrottle] 에 한 번으로 묶는다: 창이 닫혀 있으면 바로 찍고 창을 연다,
  /// 창이 열린 동안 온 줄은 창이 닫힐 때 한 번 더. 방이 안 보이면 찍지 않고 다시 보일 때로 미룬다.
  /// 방을 열 때 · 나갈 때 찍는 [markRead] 와 서버 푸시 30초 규칙은 그대로다.
  void _markReadSoon() {
    if (!_alive || !_visible || _markReadWindow != null) {
      _markReadOwed = true;
      return;
    }
    _markReadOwed = false;
    unawaited(_repository.markRead(_matchId));
    _markReadWindow = Timer(markReadThrottle, () {
      _markReadWindow = null;
      if (_markReadOwed) {
        _markReadSoon();
      }
    });
  }

  /// 시트를 스와이프로 닫았다. 강제가 아니라서 닫으면 14h 배너로 바뀐다.
  void dismissSheet() => state = state.copyWith(sheetDismissed: true);

  Future<void> retry() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    await _open();
  }
}
