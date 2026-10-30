import 'dart:convert';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:test/test.dart';

import 'mock_smtp_server.dart';

void main() {
  group('BINARYMIME Support', () {
    late MockSmtpServer mockServer;

    setUp(() async {
      mockServer = MockSmtpServer();
      await mockServer.start();
    });

    tearDown(() async {
      await mockServer.stop();
    });

    test('Sends binary content when BINARYMIME is supported', () async {
      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..subject = 'Binary Test'
        ..text = 'Hello World';

      await send(message, smtpServer);

      // Check headers capture in BDAT
      var fullData = utf8.decode(mockServer.bdatData);
      expect(fullData, contains('content-transfer-encoding: binary'));
      expect(fullData, contains('Hello World')); // Not base64 encoded
    });

    test('Falls back to Base64 when BINARYMIME is NOT supported', () async {
      mockServer.advertiseBinaryMime = false;
      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..subject = 'Base64 Test'
        ..text = 'Hello World';

      await send(message, smtpServer);

      var fullData = utf8.decode(mockServer.bdatData);
      expect(fullData, contains('content-transfer-encoding: base64'));
      expect(fullData, contains('SGVsbG8gV29ybGQNCg==')); // "Hello World" in base64
    });

    test('Handles single dot on a line correctly in BINARYMIME', () async {
      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..subject = 'Dot Test'
        ..text = 'Line 1\r\n.\r\nLine 2';

      await send(message, smtpServer);

      var fullData = utf8.decode(mockServer.bdatData);
      expect(fullData, contains('content-transfer-encoding: binary'));
      // Should contain the dot exactly as is, without stuffing (..), because it's BDAT
      expect(fullData, contains('\r\n.\r\n'));
    });

    test('Handles SMTP keywords in content correctly in BINARYMIME', () async {
      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..subject = 'Keyword Test'
        ..text = 'QUIT\r\nEHLO examples.com\r\nDATA';

      await send(message, smtpServer);

      var fullData = utf8.decode(mockServer.bdatData);
      expect(fullData, contains('content-transfer-encoding: binary'));
      expect(fullData, contains('QUIT\r\nEHLO examples.com\r\nDATA'));
    });

    test('Declares BODY=BINARYMIME on MAIL FROM', () async {
      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..text = 'Hello World';

      await send(message, smtpServer);

      expect(mockServer.serverLog, contains('MAIL FROM:<sender@example.com> BODY=BINARYMIME'));
    });

    test('Ignores BINARYMIME without CHUNKING', () async {
      mockServer.advertiseChunking = false;
      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..text = 'Line 1\r\n.\r\nRCPT TO:<attacker@example.net>';

      await send(message, smtpServer);

      expect(mockServer.serverLog, contains('MAIL FROM:<sender@example.com>'));
      expect(mockServer.serverLog, contains('content-transfer-encoding: base64'));
      expect(mockServer.serverLog, isNot(contains('RCPT TO:<attacker@example.net>')));
    });

    // Using base64 would be allowed, but is not necessary as per RFC 3030.
    test('Does not split long lines in BINARYMIME (RFC 3030 compliance)', () async {
      // RFC 3030, Section 3:
      // "Once a receiver-SMTP supporting the BINARYMIME service extension accepts a
      // message containing binary material, the receiver-SMTP MUST deliver or
      // relay the message in such a way as to preserve all bits in each octet."
      //
      // "If the receiver-SMTP does not support BINARYMIME ... a sender-SMTP has
      // three options ... Second, it may implement a gateway transformation to
      // convert the message into valid 7bit-encoded MIME."
      //
      // This implies that if we (the client) send BINARYMIME to a server that
      // supports it, WE do not need to wrap lines or encode to Base64. If that
      // server needs to relay to a non-BINARYMIME server, IT is responsible for
      // the downgrade (encoding/wrapping).

      final smtpServer = SmtpServer('localhost', port: mockServer.port, allowInsecure: true);

      // Create a line longer than the standard 76/78 character limit
      var longLine = 'a' * 1000;

      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('recipient@example.com')
        ..subject = 'Long Line Test'
        ..text = longLine;

      await send(message, smtpServer);

      var fullData = utf8.decode(mockServer.bdatData);

      // Verify appropriate header
      expect(fullData, contains('content-transfer-encoding: binary'));

      // Verify the long line was sent intact, without splitting or encoding
      expect(fullData, contains(longLine));
      expect(fullData, isNot(contains('=\r\n'))); // No quoted-printable soft breaks
      expect(fullData, isNot(contains('\r\n '))); // No header folding (though this is body)
    });
  });
}
