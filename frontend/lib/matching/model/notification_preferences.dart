/// 알림 스위치(화면 16d `NMgCa`). 서버에 행이 없으면 전부 켜짐 + 마케팅만 꺼짐이다(Task C4 기본값).
class NotificationPreferences {
  const NotificationPreferences({
    this.cardArrived = true,
    this.acceptanceReceived = true,
    this.matchMade = true,
    this.newMessage = true,
    this.trustReminder = true,
    this.newFriendReview = true,
    this.marketing = false,
    this.quietHours = true,
  });

  final bool cardArrived;
  final bool acceptanceReceived;
  final bool matchMade;
  final bool newMessage;
  final bool trustReminder;
  final bool newFriendReview;
  final bool marketing;
  final bool quietHours;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    bool read(String key, {bool fallback = true}) => json[key] as bool? ?? fallback;
    return NotificationPreferences(
      cardArrived: read('card_arrived'),
      acceptanceReceived: read('acceptance_received'),
      matchMade: read('match_made'),
      newMessage: read('new_message'),
      trustReminder: read('trust_reminder'),
      newFriendReview: read('new_friend_review'),
      marketing: read('marketing', fallback: false),
      quietHours: read('quiet_hours'),
    );
  }

  NotificationPreferences withValue(String key, bool value) {
    return NotificationPreferences(
      cardArrived: key == 'card_arrived' ? value : cardArrived,
      acceptanceReceived: key == 'acceptance_received' ? value : acceptanceReceived,
      matchMade: key == 'match_made' ? value : matchMade,
      newMessage: key == 'new_message' ? value : newMessage,
      trustReminder: key == 'trust_reminder' ? value : trustReminder,
      newFriendReview: key == 'new_friend_review' ? value : newFriendReview,
      marketing: key == 'marketing' ? value : marketing,
      quietHours: key == 'quiet_hours' ? value : quietHours,
    );
  }

  bool valueOf(String key) => switch (key) {
        'card_arrived' => cardArrived,
        'acceptance_received' => acceptanceReceived,
        'match_made' => matchMade,
        'new_message' => newMessage,
        'trust_reminder' => trustReminder,
        'new_friend_review' => newFriendReview,
        'marketing' => marketing,
        _ => quietHours,
      };
}
