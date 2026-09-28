import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기기 연락처 한 사람. 번호는 기기에 적힌 원문 그대로다 — 정규화는 서버 한 곳에서만 한다(Ruling 32).
class DeviceContact {
  const DeviceContact({required this.id, required this.name, required this.numbers});

  final String id;
  final String name;
  final List<String> numbers;
}

/// 기기 연락처와 권한. 패키지를 부르는 곳은 [FlutterContactsSource] 하나뿐이다.
abstract interface class DeviceContactSource {
  Future<bool> hasPermission();

  /// OS 권한 창을 띄운다. "다시 묻지 않음"이면 창 없이 곧바로 false 가 온다.
  Future<bool> requestPermission();

  Future<void> openSettings();

  /// 번호가 하나라도 있는 연락처만, 기기가 주는 순서대로.
  Future<List<DeviceContact>> fetchAll();
}

/// `flutter_contacts` 2.5 v2 API. 플랫폼 채널이라 단위 테스트 대신 Fake 로 갈아 끼운다.
class FlutterContactsSource implements DeviceContactSource {
  const FlutterContactsSource();

  /// `granted` 와 `limited`(iOS 18 "일부 연락처만 허용")를 허용으로 본다 — 패키지의 `has` 가 이 판정이다.
  @override
  Future<bool> hasPermission() => FlutterContacts.permissions.has(PermissionType.read);

  @override
  Future<bool> requestPermission() async => switch (await FlutterContacts.permissions.request(PermissionType.read)) {
        PermissionStatus.granted || PermissionStatus.limited => true,
        _ => false,
      };

  @override
  Future<void> openSettings() => FlutterContacts.permissions.openSettings();

  @override
  Future<List<DeviceContact>> fetchAll() async {
    final contacts = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
    return [
      // Contact.id 는 String? 다 — 저장된 연락처는 늘 id 가 있다. 없으면 선택을 구별할 수 없어 뺀다.
      for (final contact in contacts)
        if (contact.id case final id? when contact.phones.isNotEmpty)
          DeviceContact(
            id: id,
            name: contact.displayName ?? '',
            numbers: [for (final phone in contact.phones) phone.number],
          ),
    ];
  }
}

final deviceContactSourceProvider = Provider<DeviceContactSource>((ref) => const FlutterContactsSource());
