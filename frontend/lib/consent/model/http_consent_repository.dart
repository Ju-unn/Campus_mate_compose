import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/consent/model/consent_item.dart';
import 'package:campus_mate/consent/model/consent_repository.dart';
import 'package:campus_mate/core/http/api_client.dart';

/// [ConsentRepository]를 FastAPI 호출로 구현한다(backend/app/consents/router.py).
class HttpConsentRepository implements ConsentRepository {
  const HttpConsentRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<void>> submit({required Set<ConsentItem> agreed}) => _api.send(
        'POST',
        '/me/consents',
        (_) {},
        body: {
          'agreed': [
            for (final item in ConsentItem.values)
              if (item.isRequired && agreed.contains(item)) item.wireName,
          ],
          'marketing': agreed.contains(ConsentItem.marketing),
        },
      );
}
