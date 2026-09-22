import 'package:campus_mate/chat/model/chat_repository.dart';
import 'package:campus_mate/chat/model/http_chat_repository.dart';
import 'package:campus_mate/chat/model/message_stream.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 조각 5 화면들이 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return HttpChatRepository(ref.read(apiClientProvider));
});

/// 채팅방이 살아 있는 동안만 쓰는 실시간 통로. 테스트는 `FakeMessageStream` 으로 덮어쓴다.
final messageStreamProvider = Provider<MessageStream>((ref) {
  return RealtimeMessageStream(Supabase.instance.client);
});
