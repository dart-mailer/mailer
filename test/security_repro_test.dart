import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/src/mime/mime.dart';
import 'package:mailer/src/smtp/capabilities.dart';
import 'package:mailer/src/smtp/connection.dart';
import 'package:mailer/src/smtp/validator.dart';
import 'package:mailer/smtp_server.dart';
import 'package:test/test.dart';

Message message() => Message()
  ..from = 'sender@example.com'
  ..recipients.add('recipient@example.com')
  ..text = 'hello';

Future<String> wire(Message value) async => utf8
    .decode(await MimeMessage(value).data(const Capabilities()).expand((part) => part).toList());

void main() {
  test('BCC command injection is rejected before SMTP', () {
    final value = message()
      ..bccRecipients.add('victim@example.com>\r\nRCPT TO:<attacker@example.net');
    expect(validate(value).map((problem) => problem.code), contains('RECIPIENT_ADDRESS'));
  });

  test('folded command is rejected by envelope and MIME validation', () {
    const address = 'victim(comment\r\nNOOP\r\n)@example.com';
    final value = message()
      ..validator = const StrictAddressValidator()
      ..from = const Address(address);
    expect(validate(value).map((problem) => problem.code),
        containsAll(['ENV_FROM', 'INVALID_HEADER']));
    value.envelopeFrom = 'safe@example.com';
    expect(validate(value).map((problem) => problem.code), contains('INVALID_HEADER'));
  });

  test('custom header name cannot write an extra MIME header', () {
    final value = message()..headers['x-original\r\nx-injected'] = 'yes';
    expect(validate(value).map((problem) => problem.code), contains('INVALID_HEADER'));
  });

  test('attachment custom header name cannot write an extra MIME header', () {
    final attachment = StringAttachment('x')..additionalHeaders['x-original\r\nx-injected'] = 'yes';
    final value = message()..attachments.add(attachment);
    expect(validate(value).map((problem) => problem.code), contains('INVALID_HEADER'));
  });

  test('address-valued custom header cannot write an extra MIME header', () async {
    final value = message()
      ..headers['reply-to'] = const Address('a@example.com\r\nx-injected: yes');
    await expectLater(wire(value), throwsA(isA<InvalidHeaderException>()));
  });

  test('attachment filename remains inside its quoted parameter', () async {
    final value = message()
      ..attachments.add(StringAttachment('x', fileName: 'a"; x-injected="yes'));
    expect(await wire(value), contains('filename="a\\"; x-injected=\\"yes"'));
  });

  test('SMTP command CRLF is rejected before any command is written', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final commands = <String>[];
    Socket? peerSocket;
    server.listen((peer) {
      peerSocket = peer;
      utf8.decoder.bind(peer).transform(const LineSplitter()).listen((line) {
        commands.add(line);
        peer.write('250 OK\r\n');
      });
    });

    final connection = Connection(SmtpServer('127.0.0.1', port: server.port, allowInsecure: true));
    try {
      await connection.connect();
      await expectLater(
        connection.send('RCPT TO:<victim@example.com>\r\nRCPT TO:<attacker@example.net>'),
        throwsA(isA<SmtpClientCommunicationException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands, isEmpty);
    } finally {
      peerSocket?.destroy();
      await connection.close();
      await server.close();
    }
  });

  test('private SMTP command is redacted on unexpected response', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((peer) {
      utf8.decoder.bind(peer).transform(const LineSplitter()).listen((_) {
        peer.write('535 rejected\r\n');
      });
    });

    final connection = Connection(SmtpServer('127.0.0.1', port: server.port, allowInsecure: true));
    try {
      await connection.connect();
      await expectLater(
        connection.send('c2Vuc2l0aXZl', acceptedRespCodes: ['334'], private: true),
        throwsA(isA<SmtpClientCommunicationException>()
            .having((error) => error.toString(), 'error', isNot(contains('c2Vuc2l0aXZl')))),
      );
    } finally {
      await connection.close();
      await server.close();
    }
  });

  test('SMTP continuation responses are bounded', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((peer) {
      utf8.decoder.bind(peer).transform(const LineSplitter()).listen((_) {
        peer.write('${'250-continue\r\n' * 101}250 done\r\n');
      });
    });

    final connection = Connection(SmtpServer('127.0.0.1', port: server.port, allowInsecure: true));
    try {
      await connection.connect();
      await expectLater(
          connection.send('EHLO local'), throwsA(isA<SmtpClientCommunicationException>()));
    } finally {
      await connection.close();
      await server.close();
    }
  });

  test('one overlong SMTP response line is rejected', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((peer) {
      utf8.decoder.bind(peer).transform(const LineSplitter()).listen((_) {
        peer.write('250 ${'x' * 9000}\r\n');
      });
    });

    final connection = Connection(SmtpServer('127.0.0.1', port: server.port, allowInsecure: true));
    try {
      await connection.connect();
      await expectLater(
          connection.send('EHLO local'), throwsA(isA<SmtpClientCommunicationException>()));
    } finally {
      await connection.close();
      await server.close();
    }
  });

  test('persistent send validates before connecting', () async {
    final value = message()
      ..bccRecipients.add('victim@example.com>\r\nRCPT TO:<attacker@example.net');
    final connection = PersistentConnection(SmtpServer('127.0.0.1', port: 1));
    try {
      await expectLater(connection.send(value), throwsA(isA<SmtpMessageValidationException>()));
    } finally {
      await connection.close();
    }
  });
}
