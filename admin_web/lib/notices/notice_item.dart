/// 공지사항 데이터. 서버 모양은 backend/app/admin/notices.py 의 `_view`. 제목 · 본문은 손대지 않고 그대로 들고 있다 —
/// 화면은 일반 Text 로만 그린다.
library;

import 'dart:typed_data';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/reports/report_dialogs.dart' show dialogFailedText;

/// 올릴 그림 한 장(관리자가 고른 파일). 이름은 multipart 의 filename — 없으면 서버가 파일 칸으로 받지 않는다.
typedef NoticeImage = ({Uint8List bytes, String name});

/// 서버 그림 상한(backend MAX_IMAGE_BYTES)과 같다 — 넘는 그림은 보내기 전에 막는다.
const int maxNoticeImageBytes = 10 * 1024 * 1024;

/// 만들기 실패 → 대화상자 오류 줄. 그림 오류(422 detail image_type · image_too_large)는 따로, 그 밖은 일반 실패 글자.
String noticeSaveErrorText(AdminApiFailure failure) {
  return switch (failure.reason) {
    'image_type' => '올릴 수 없는 그림이에요. JPG · PNG · WEBP 그림을 골라 주세요.',
    'image_too_large' => noticeImageTooLargeText,
    _ => dialogFailedText,
  };
}

const String noticeImageTooLargeText = '그림이 10MB 를 넘어요. 더 작은 그림을 골라 주세요.';

/// 고른 파일이 [maxNoticeImageBytes] 를 넘는다 — 그림 고르기가 바이트를 읽기 전에 던진다.
class NoticeImageTooLarge implements Exception {
  const NoticeImageTooLarge();
}

/// 공지 한 줄(가린 공지 포함).
class NoticeItem {
  const NoticeItem({
    required this.id,
    required this.title,
    required this.text,
    required this.imageUrl,
    required this.blinded,
    required this.createdAt,
    required this.createdAtRaw,
  });

  final String id;
  final String title;
  final String text;
  final String? imageUrl;

  /// 관리자가 가렸다(status blinded) — 앱에는 안 보인다
  final bool blinded;
  final DateTime createdAt;

  /// 서버가 준 created_at 글자 그대로 — 다음 쪽 커서. 웹 DateTime 은 밀리초까지라 다시 만들면 마이크로초가 잘려 줄을 건너뛴다.
  final String createdAtRaw;

  /// 목록 "내용" 칸 — 첫 줄만
  String get firstLine => text.split('\n').first;

  static NoticeItem fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'title': final String title,
      'text': final String text,
      'image_url': final String? imageUrl,
      'status': final String status,
      'created_at': final String createdAt,
    }) {
      final at = DateTime.tryParse(createdAt);
      if (at != null) {
        return NoticeItem(
          id: id,
          title: title,
          text: text,
          imageUrl: imageUrl,
          blinded: status == 'blinded',
          createdAt: at,
          createdAtRaw: createdAt,
        );
      }
    }
    throw const FormatException('공지 한 줄의 모양이 아니에요');
  }
}
