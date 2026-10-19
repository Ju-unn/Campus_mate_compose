import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// FlutterContactsSource 는 플랫폼 채널을 부르는 얇은 껍데기다. 권한 상태를 읽는 isLimited 만 채널 가짜로 확인한다.
// 화면 · 뷰모델 테스트는 fake_contact_blocks.dart 의 FakeDeviceContactSource 로 대신한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 네이티브가 `permissions.check` 에 [status] 글자를 돌려준 것처럼 꾸민다(iOS 18 이면 "limited").
  void nativeReports(String status) {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_contacts'), (call) async {
      expect(call.method, 'permissions.check');
      return status;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel('flutter_contacts'), null));
  }

  test('isLimited is true only when the OS reports limited (iOS 18 일부 연락처만 허용)', () async {
    nativeReports('limited');

    expect(await const FlutterContactsSource().isLimited(), isTrue);
  });

  for (final status in ['granted', 'denied', 'permanentlyDenied', 'restricted', 'notDetermined']) {
    test('isLimited is false when the OS reports $status', () async {
      nativeReports(status);

      expect(await const FlutterContactsSource().isLimited(), isFalse);
    });
  }

  test('DeviceContact keeps id, name and every number as given', () {
    const contact = DeviceContact(id: 'c1', name: '엄마', numbers: ['010-1111-2841', '02-123-4567']);

    expect(contact.id, 'c1');
    expect(contact.name, '엄마');
    expect(contact.numbers, ['010-1111-2841', '02-123-4567']);
  });
}
