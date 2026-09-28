import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:flutter_test/flutter_test.dart';

// FlutterContactsSource 는 플랫폼 채널을 부르는 얇은 껍데기라 단위 테스트하지 않는다.
// 화면 · 뷰모델 테스트는 fake_contact_blocks.dart 의 FakeDeviceContactSource 로 대신한다.
void main() {
  test('DeviceContact keeps id, name and every number as given', () {
    const contact = DeviceContact(id: 'c1', name: '엄마', numbers: ['010-1111-2841', '02-123-4567']);

    expect(contact.id, 'c1');
    expect(contact.name, '엄마');
    expect(contact.numbers, ['010-1111-2841', '02-123-4567']);
  });
}
