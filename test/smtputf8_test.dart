import 'dart:convert';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:test/test.dart';

import 'mock_smtp_server.dart';

void main() {
  group('SMTPUTF8', () {
    late MockSmtpServer mockServer;
    late SmtpServer smtpServer;

    setUp(() async {
      mockServer = MockSmtpServer()
        ..advertiseSmtpUtf8 = true
        ..advertiseBinaryMime = false;
      await mockServer.start();
      smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
    });

    tearDown(() async {
      await mockServer.stop();
    });

    test('Is not used if all local parts are ASCII (#279)', () async {
      final message = Message()
        ..from = const Address('a@example.test', 'Société Dupont')
        ..recipients.add(const Address('info@müller.test'))
        ..subject = 'Facture n° 12'
        ..text = 'x';

      await send(message, smtpServer);

      expect(mockServer.serverLog, contains('MAIL FROM:<a@example.test>'));
      expect(mockServer.serverLog, contains('RCPT TO:<info@xn--mller-kva.test>'));
      final data = utf8.decode(mockServer.bdatData);
      expect(data, isNot(contains('Société')));
      expect(data, isNot(contains('Facture n° 12')));
      expect(data, contains('subject: =?utf-8?B?'));
      expect(data, contains('to: info@xn--mller-kva.test'));
    });

    test('Is used for a non-ASCII local part in the envelope', () async {
      final message = Message()
        ..from = const Address('jörg@example.test', 'Jörg')
        ..recipients.add('info@example.test')
        ..subject = 'Grüße'
        ..text = 'x';

      await send(message, smtpServer);

      expect(mockServer.serverLog, contains('MAIL FROM:<jörg@example.test> SMTPUTF8'));
      final data = utf8.decode(mockServer.bdatData);
      expect(data, contains('subject: Grüße'));
    });

    test('Is used for a non-ASCII local part only in a header', () async {
      final message = Message()
        ..from = 'a@example.test'
        ..recipients.add('info@example.test')
        ..headers['reply-to'] = const Address('jörg@example.test')
        ..text = 'x';

      await send(message, smtpServer);

      expect(mockServer.serverLog, contains('MAIL FROM:<a@example.test> SMTPUTF8'));
    });

    test('Is not used if the server does not support it', () async {
      mockServer.advertiseSmtpUtf8 = false;
      final message = Message()
        ..from = 'jörg@example.test'
        ..recipients.add('info@example.test')
        ..text = 'x';

      await send(message, smtpServer);

      expect(mockServer.serverLog, contains('MAIL FROM:<jörg@example.test>'));
    });
  });
}
