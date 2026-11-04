import 'package:campus_mate/chat/model/chat_room.dart';
import 'package:campus_mate/chat/model/conversation.dart';
import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/model/message_page.dart';
import 'package:campus_mate/common/result.dart';

/// 조각 5 가 쓰는 서버 호출 전부. 화면은 이 인터페이스만 보고 `Http…` 구현을 모른다.
///
/// **거절 전용 호출이 없다** — 게이트 거절은 [leave] 다(결정 11).
abstract interface class ChatRepository {
  Future<Result<List<Conversation>>> fetchConversations();
  Future<Result<ChatRoom>> fetchRoom(String matchId);

  /// [before] · [beforeId] 는 화면에 있는 **가장 오래된 줄** 의 값을 그대로 보낸다.
  /// 시각만 보내면 같은 시각에 들어간 두 줄이 페이지 경계에서 한 줄 빠진다.
  Future<Result<MessagePage>> fetchMessages(String matchId, {DateTime? before, String? beforeId});

  /// 보낸 줄을 돌려준다. 모르는 종류였다면 null 이고, 그때는 구독이 붙여 준다.
  Future<Result<Message?>> sendMessage(String matchId, String body);

  /// 방에 들어올 때 · 나갈 때, 그리고 방을 보는 동안 받은 상대 줄을 몇 초에 한 번으로 묶어서.
  /// 상대 화면의 내 줄 '1' 이 이 시각으로 사라진다(사용자 결정 2026-10-13).
  Future<Result<void>> markRead(String matchId);

  /// 상대가 마지막으로 읽은 시각만 가볍게 묻는다 — 메시지 목록을 1건으로 불러 그 값만 쓴다.
  /// 방 머리말을 묻지 않는 까닭: 부를 때마다 실사진 서명 URL 이 새로 만들어져 앱바 아바타가 깜박인다.
  Future<Result<PartnerRead>> fetchPartnerRead(String matchId);

  /// 나가기 = 게이트 거절(결정 11). 되돌릴 수 없고 상대에게 시스템 줄로 보인다.
  Future<Result<void>> leave(String matchId);

  Future<Result<TrustAcceptOutcome>> acceptTrust(String matchId);
}
