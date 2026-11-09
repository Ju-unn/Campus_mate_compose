import 'dart:io';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 에러 문구를 글자로 바꾸는 곳(`error_text.dart`)을 지킨다. 문구는 옮기기만 했으므로 기대값은 옛 `failure.dart` 의 글자 그대로다.
void main() {
  final l10n = AppLocalizationsKo();

  /// 구체 `Failure` 하나마다 (객체, 화면에 나가는 글자). 하위 형을 더하면 아래 "빠짐없이" 시험이 이 표를 채우라고 알린다.
  final cases = <(Failure, String)>[
    (const NetworkFailure(), '네트워크 연결을 확인해 주세요'),
    (const SessionExpiredFailure(), '세션이 만료됐어요, 다시 로그인해 주세요'),
    (const SessionRejectedFailure(), '세션이 만료됐어요, 다시 로그인해 주세요'),
    (const NotFoundFailure(), '요청한 정보를 찾을 수 없습니다'),
    (const UnknownFailure(), '알 수 없는 오류가 발생했습니다'),
    (const ServerUnavailableFailure(), '잠시 뒤 다시 시도해 주세요'),
    (const RateLimitedFailure(), '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요'),
    (const RateLimitedFailure('내일 다시 시도해 주세요'), '내일 다시 시도해 주세요'),
    (const SignUpRejectedFailure('가입을 받을 수 없는 학교예요'), '가입을 받을 수 없는 학교예요'),
    (const WrongCodeFailure(), '코드가 맞지 않아요. 다시 확인해 주세요.'),
    (const ServerRejectedFailure('서버가 거절한 이유', code: 'X'), '서버가 거절한 이유'),
    (const SuspendedFailure(), '이용이 제한된 계정이에요'),
    (const WithdrawnFailure(), '탈퇴한 계정이에요'),
    (const CodeNotSentFailure(), '인증번호를 보내지 못했어요. 잠시 뒤 다시 시도해 주세요'),
    (const SchoolEmailIncompleteFailure(), '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요'),
    (const SchoolEmailNotConfirmedFailure(), '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요'),
    (const SchoolEmailSameAsLoginFailure(), '로그인에 쓰는 구글·카카오 계정과 같은 메일은 쓸 수 없어요. 다른 학교 메일을 입력해 주세요'),
    (const SchoolEmailRejectedFailure('등록되지 않은 학교 메일이에요'), '등록되지 않은 학교 메일이에요'),
    (const SchoolEmailTakenFailure('서버 문구', 'kakao'), '이미 카카오로 가입된 학교 메일이에요'),
    (const SchoolEmailTakenFailure('서버 문구', 'google', myProvider: 'kakao'), '이미 구글로 가입된 학교 메일이에요'),
    (const SchoolEmailTakenFailure('서버 문구', 'apple'), '이미 애플로 가입된 학교 메일이에요'),
    (const SchoolEmailTakenFailure('서버 문구', 'kakao', myProvider: 'kakao'), '이미 가입된 학교 메일이에요'),
    (const SchoolEmailTakenFailure('서버 문구', 'email'), '이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요'),
    (const SchoolEmailTakenFailure('서버가 준 문구', 'github'), '서버가 준 문구'),
    (const LoginCancelledFailure(), '로그인이 취소됐어요'),
    (const SocialLoginFailure(), '로그인하지 못했어요. 잠시 뒤 다시 시도해 주세요'),
    (const AppErrorFailure(AppError.notificationsLoad), '알림을 불러오지 못했어요'),
    (const AppErrorFailure(AppError.tryLater), '잠시 후 다시 시도해 주세요'),
    (const AppErrorFailure(AppError.storeOpenFailed), '스토어를 열지 못했어요. 스토어에서 CampusMate 를 검색해 주세요.'),
    (const AppErrorFailure(AppError.photoUnreadable), '사진을 다시 확인해 주세요'),
    (const AppErrorFailure(AppError.graduateEmailInvalid), '이전 학교 메일 형식을 다시 확인해 주세요'),
    (const AppErrorFailure(AppError.accountLoad), '잠시 뒤 다시 시도해 주세요'),
    (const AppErrorFailure(AppError.contactNoMobile), '휴대전화 번호가 있는 연락처만 차단할 수 있어요'),
    (const AppErrorFailure(AppError.friendCodeNotFound), '코드를 찾을 수 없어요. 다시 확인해 주세요.'),
    (const AppErrorFailure(AppError.friendCodeTryLater), '잠시 후 다시 시도해 주세요.'),
    (const AppErrorFailure(AppError.friendReviewAlreadyWritten), '이미 리뷰를 남겼어요'),
    (const AppErrorFailure(AppError.reportLimited), '오늘은 더 신고할 수 없어요'),
    (const AppErrorFailure(AppError.pollDailyLimit), '오늘은 질문을 더 올릴 수 없어요'),
    (const AppErrorFailure(AppError.chatGateOver), '응답 기한이 지나 이 대화는 종료됐어요'),
    (const AppErrorFailure(AppError.nicknameInvalid), '한글 또는 영문 2~5자로 입력해 주세요'),
    (const AppErrorFailure(AppError.nicknameTaken), '이미 있는 닉네임이에요'),
    (const AppErrorFailure(AppError.heightRange), '120~230 사이로 입력해 주세요'),
    (const AppErrorFailure(AppError.phoneInvalid), '올바른 휴대폰 번호를 입력해 주세요'),
    (const BirthYearFailure(2007), '2007년생부터 가입할 수 있어요'),
    (const AppErrorFailure(AppError.saveFailed), '저장하지 못했어요. 잠시 후 다시 시도해 주세요'),
    (const AppErrorFailure(AppError.noFace), '얼굴이 보이는 사진을 골라 주세요'),
    (const AppErrorFailure(AppError.meLoad), '잠시 뒤 다시 시도해 주세요'),
    (const AppErrorFailure(AppError.heartTaskMonthlyLimit), '이번 달에는 더 인증할 수 없어요'),
    (const AppErrorFailure(AppError.cardsLoad), '카드를 불러오지 못했어요'),
    (const AppErrorFailure(AppError.photoDocument), '학생증·신분증처럼 글자가 많은 사진은 올릴 수 없어요. 얼굴이 잘 나온 일반 사진을 올려 주세요'),
    (const AppErrorFailure(AppError.bioDraft), '초안을 만들지 못했어요. 직접 써 주세요'),
    (const PhotoMaxFailure(4), '사진은 최대 4장까지 올릴 수 있어요'),
    (const PhotoRejectedFailure(2), '2장은 얼굴이 보이지 않아 빠졌어요'),
    (const NoteTooShortFailure(10), '10자 이상 입력해 주세요'),
  ];

  group('failureText', () {
    for (final (failure, expected) in cases) {
      test('${failure.runtimeType} → $expected', () {
        expect(failureText(l10n, failure), expected);
      });
    }

    test('모든 구체 Failure 하위 형이 위 표에 들어 있다 — 새 하위 형을 더하면 이 표에도 글자를 적는다', () {
      final declared = RegExp(r'^final class (\w+) extends \w+', multiLine: true)
          .allMatches(File('lib/common/failure.dart').readAsStringSync())
          .map((match) => match.group(1)!)
          .toSet();
      final covered = {for (final (failure, _) in cases) failure.runtimeType.toString()};

      expect(covered, declared);
    });

    test('임시 껍데기 toDisplayMessage() 는 같은 글자를 돌려준다', () {
      for (final (failure, expected) in cases) {
        expect(failure.toDisplayMessage(), expected, reason: '${failure.runtimeType}');
      }
    });
  });

  group('appErrorKindText', () {
    test('앱이 정하는 에러 종류마다 비지 않은 글자가 있다', () {
      for (final error in AppError.values) {
        expect(appErrorKindText(l10n, error), isNotEmpty, reason: '$error');
      }
    });
  });

  group('학교 메일 중복 안내 둘째 줄 · 다시 로그인 알림', () {
    test('다른 소셜이 쥔 메일이면 그 소셜로 로그인하라고 안내한다', () {
      const failure = SchoolEmailTakenFailure('서버', 'google');

      expect(takenHintText(l10n, failure), '구글로 로그인해 주세요');
      expect(takenReloginNoticeText(l10n, failure), '이 학교 메일은 구글로 가입돼 있어요. 구글로 로그인해 주세요');
    });

    test('내 소셜이 쥔 메일이면 계정 하나 안내만 하고 다시 로그인 알림은 없다', () {
      const failure = SchoolEmailTakenFailure('서버', 'kakao', myProvider: 'kakao');

      expect(takenHintText(l10n, failure), '한 학교 메일로는 계정 하나만 만들 수 있어요');
      expect(takenReloginNoticeText(l10n, failure), isNull);
    });

    test('소셜이 쥔 메일이 아니면 둘째 줄도 알림도 없다', () {
      for (final provider in ['email', 'github']) {
        final failure = SchoolEmailTakenFailure('서버', provider);

        expect(takenHintText(l10n, failure), isNull, reason: provider);
        expect(takenReloginNoticeText(l10n, failure), isNull, reason: provider);
      }
    });
  });

  group('context.errorText · context.appErrorText', () {
    Future<BuildContext> pump(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) {
            captured = context;
            return const SizedBox();
          }),
        ),
      );
      return captured;
    }

    testWidgets('화면의 BuildContext 로 Failure · 에러 종류를 글자로 바꾼다', (tester) async {
      final context = await pump(tester);

      expect(context.errorText(const NetworkFailure()), '네트워크 연결을 확인해 주세요');
      expect(context.appErrorText(AppError.tryLater), '잠시 후 다시 시도해 주세요');
    });

    testWidgets('위임자가 없는 MaterialApp(시험)에서도 한국어로 바뀐다', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      })));

      expect(captured.errorText(const UnknownFailure()), '알 수 없는 오류가 발생했습니다');
    });
  });
}
