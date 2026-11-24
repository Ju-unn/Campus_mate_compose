import 'dart:convert';

import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/notices/notice_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notice_fakes.dart';

/// 공지사항 API — 서버 계약은 backend/app/admin/notices.py(목록 커서 · multipart 만들기 · 사유 지우기)
void main() {
  test('목록: 첫 쪽은 커서 없이 받고, 줄을 읽는다(그림 · 가림 상태)', () async {
    final server = FakeNoticeServer(rows: [
      noticeRow('n1', title: '점검 안내', text: '오늘 밤 점검해요', imageUrl: 'https://storage.test/n1.jpg'),
      noticeRow('n2', status: 'blinded', createdAt: '2026-11-23T01:00:00+00:00'),
    ]);

    final page = await server.api().listNotices();

    expect(server.lists.single.url.queryParameters, isEmpty);
    expect(page.hasMore, isFalse);
    expect([for (final n in page.items) (n.id, n.title, n.text, n.imageUrl, n.blinded)], [
      ('n1', '점검 안내', '오늘 밤 점검해요', 'https://storage.test/n1.jpg', false),
      ('n2', '공지 제목', '공지 본문', null, true),
    ]);
  });

  test('목록: 다음 쪽은 마지막 줄의 created_at(서버 글자 그대로) · id 를 before · before_id 로 보낸다', () async {
    final server = FakeNoticeServer(rows: [
      for (var i = 0; i < 25; i++) noticeRow('n${i.toString().padLeft(2, '0')}', createdAt: '2026-11-24T01:00:${i.toString().padLeft(2, '0')}.123456+00:00'),
    ]);

    final first = await server.api().listNotices();
    final second = await server.api().listNotices(after: first.items.last);

    expect((first.items.length, first.hasMore), (20, true));
    expect(server.lists.last.url.queryParameters, {'before': '2026-11-24T01:00:05.123456+00:00', 'before_id': 'n05'});
    expect(second.items.map((n) => n.id), ['n04', 'n03', 'n02', 'n01', 'n00']);
    expect(second.hasMore, isFalse);
  });

  test('목록 모양이 틀리면 실패로 바꾼다', () {
    expect(() => NoticeItem.fromJson({'id': 'n1'}), throwsFormatException);
  });

  test('만들기: 그림이 없으면 multipart 에 image 칸이 아예 없다(제목 · 본문은 앞뒤 공백을 떼고)', () async {
    final server = FakeNoticeServer();

    await server.api().createNotice(title: ' 점검 안내 ', body: '오늘 밤 점검해요\n');

    final request = server.creates.single;
    final form = FakeNoticeServer.formText(request);
    expect(request.headers['content-type'], startsWith('multipart/form-data'));
    expect(request.headers['authorization'], 'Bearer token-test');
    // 칸 머리 뒤(한글 칸은 content-type 줄이 더 붙는다) 빈 줄 다음이 값이다
    expect(form, contains(RegExp('name="title"\r\n(?:[^\r\n]+\r\n)*\r\n점검 안내\r\n--')));
    expect(form, contains(RegExp('name="body"\r\n(?:[^\r\n]+\r\n)*\r\n오늘 밤 점검해요\r\n--')));
    expect(form, isNot(contains('name="image"')));
  });

  test('만들기: 그림을 고르면 image 칸에 파일 이름과 바이트를 싣는다', () async {
    final server = FakeNoticeServer();

    await server.api().createNotice(title: '제목', body: '본문', image: (bytes: tinyPng, name: 'notice.png'));

    final request = server.creates.single;
    expect(FakeNoticeServer.formText(request), contains('name="image"; filename="notice.png"'));
    expect(_contains(request.bodyBytes, tinyPng), isTrue);
  });

  test('만들기: 그림 오류 422 는 detail 을 이유로 들고 실패한다', () async {
    final server = FakeNoticeServer()
      ..createFailure = 422
      ..createReason = 'image_too_large';

    await expectLater(
      server.api().createNotice(title: '제목', body: '본문', image: (bytes: tinyPng, name: 'big.png')),
      throwsA(isA<AdminApiFailure>().having((f) => (f.statusCode, f.reason), 'status · reason', (422, 'image_too_large'))),
    );
  });

  test('지우기: DELETE /admin/notices/{id} 에 사유를 JSON 본문으로 보낸다', () async {
    final server = FakeNoticeServer(rows: [noticeRow('n1')]);

    await server.api().deleteNotice('n1', '  잘못 올렸어요 ');

    final request = server.deletes.single;
    expect(request.url.path, '/admin/notices/n1');
    expect(jsonDecode(request.body), {'reason': '잘못 올렸어요'});
  });

  test('그림 오류 글자: image_type · image_too_large 는 따로, 그 밖은 일반 실패 글자', () {
    expect(noticeSaveErrorText(const AdminApiFailure(422, 'image_type')), '올릴 수 없는 그림이에요. JPG · PNG · WEBP 그림을 골라 주세요.');
    expect(noticeSaveErrorText(const AdminApiFailure(422, 'image_too_large')), '그림이 10MB 를 넘어요. 더 작은 그림을 골라 주세요.');
    expect(noticeSaveErrorText(const AdminApiFailure(null)), '처리하지 못했어요. 다시 시도해 주세요.');
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length && hit; j++) {
      hit = haystack[i + j] == needle[j];
    }
    if (hit) return true;
  }
  return false;
}
