import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:mailer/src/smtp/capabilities.dart';
import 'package:mailer/src/smtp/connection.dart';
import 'package:mailer/src/smtp/smtp_client.dart' as client;
import 'package:test/test.dart';

SmtpServer incorrectCredentials = gmail('mister@gmail.com', 'wrongpass');

Message _message() => Message()
  ..from = 'sender@example.com'
  ..recipients.add('recipient@example.com')
  ..text = 'hello';

/// Records commands instead of sending them.
class _RecordingConnection extends Connection {
  final commands = <String>[];

  _RecordingConnection() : super(SmtpServer('localhost')) {
    capabilities = const Capabilities();
  }

  @override
  Future<ServerResponse?> send(String command,
      {List<String>? acceptedRespCodes = const ['2'],
      String? expect,
      bool waitForResponse = true,
      bool private = false}) async {
    commands.add(command);
    return ServerResponse('250', ['OK']);
  }

  @override
  Future<void> sendStream(Stream<List<int>> stream) => stream.drain<void>();
}

/// A loopback smtp server which answers every received line with [respond].
class _ScriptedServer {
  late ServerSocket _listener;
  final _peers = <Socket>[];
  final commands = <String>[];
  int connections = 0;

  SmtpServer get config => SmtpServer('127.0.0.1', port: _listener.port, allowInsecure: true);

  Future<void> start(void Function(Socket peer, String line, int connection) respond,
      {bool greeting = true}) async {
    _listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _listener.listen((peer) {
      _peers.add(peer);
      final connection = ++connections;
      if (greeting) peer.write('220 ready\r\n');
      utf8.decoder.bind(peer).transform(const LineSplitter()).listen((line) {
        commands.add(line);
        respond(peer, line, connection);
      }, onError: (Object _) {});
    });
  }

  Future<void> stop() async {
    for (final peer in _peers) {
      peer.destroy();
    }
    await _listener.close();
  }
}

void main() {
  test('SmtpClient.checkCredentials() throws SmtpClientAuthenticationException', () async {
    expect(checkCredentials(incorrectCredentials, timeout: const Duration(seconds: 5)),
        throwsA(TypeMatcher<SmtpClientAuthenticationException>()));
  }); // Removed skip: false as it's default

  group('envelope', () {
    const attack = 'sender@example.com> RET=HDRS ENVID=owned';
    final setters = <String, void Function(Message)>{
      'envelopeFrom': (m) => m.envelopeFrom = attack,
      'envelopeTos': (m) => m.envelopeTos = [attack],
      'recipients': (m) => m.recipients.add(attack),
      'ccRecipients': (m) => m.ccRecipients.add(attack),
      'bccRecipients': (m) => m.bccRecipients.add(attack),
      'bccRecipients (CRLF)': (m) =>
          m.bccRecipients.add('victim@example.com>\r\nRCPT TO:<attacker@example.net'),
    };
    for (final entry in setters.entries) {
      test('unsafe ${entry.key} is rejected before any command is sent', () async {
        final message = _message();
        entry.value(message);
        final connection = _RecordingConnection();
        await expectLater(client.sendSingleMessage(message, connection, null),
            throwsA(isA<SmtpClientCommunicationException>()));
        expect(connection.commands, isEmpty);
      });
    }

    for (final address in [
      '"quoted>name"@example.com',
      r'"quoted\">name"@example.com',
      'user(comment)@example.com',
      'user@example.com.',
    ]) {
      test('$address is sent unchanged', () async {
        final message = _message()
          ..envelopeFrom = address
          ..envelopeTos = [address];
        final connection = _RecordingConnection();
        await client.sendSingleMessage(message, connection, null);
        expect(connection.commands.take(2), ['MAIL FROM:<$address>', 'RCPT TO:<$address>']);
      });
    }

    test('empty envelopeFrom is sent as null reverse-path', () async {
      final message = _message()..envelopeFrom = '';
      final connection = _RecordingConnection();
      await client.sendSingleMessage(message, connection, null);
      expect(connection.commands.first, 'MAIL FROM:<>');
    });

    test('empty envelopeTos entry is rejected', () async {
      final message = _message()..envelopeTos = [''];
      final connection = _RecordingConnection();
      await expectLater(client.sendSingleMessage(message, connection, null),
          throwsA(isA<SmtpClientCommunicationException>()));
      expect(connection.commands, isEmpty);
    });
  });

  group('Connection', () {
    late _ScriptedServer server;
    late Connection connection;

    Future<void> start(void Function(Socket peer, String line) respond, {Duration? timeout}) async {
      server = _ScriptedServer();
      await server.start((peer, line, _) => respond(peer, line), greeting: false);
      connection = Connection(server.config, timeout: timeout);
      await connection.connect();
    }

    tearDown(() async {
      await server.stop();
      await connection.close();
    });

    test('command with CRLF is rejected before it is written', () async {
      await start((peer, _) => peer.write('250 OK\r\n'));
      await expectLater(
          connection.send('RCPT TO:<victim@example.com>\r\nRCPT TO:<attacker@example.net>'),
          throwsA(isA<SmtpClientCommunicationException>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.commands, isEmpty);
    });

    test('private command is hidden in errors, server response is not', () async {
      await start((peer, _) => peer.write('535 rejected\r\n'));
      await expectLater(
          connection.send('c2Vuc2l0aXZl', acceptedRespCodes: ['334'], private: true),
          throwsA(isA<SmtpClientCommunicationException>().having((e) => e.toString(), 'message',
              allOf(isNot(contains('c2Vuc2l0aXZl')), contains('535 rejected')))));
    });

    test('number of continuation lines is limited', () async {
      await start((peer, _) => peer.write('${'250-continue\r\n' * 100}250 done\r\n'));
      await expectLater(
          connection.send('EHLO local'), throwsA(isA<SmtpClientCommunicationException>()));
    });

    test('line length is limited', () async {
      await start((peer, _) => peer.write('250 ${'x' * 9000}\r\n'));
      await expectLater(
          connection.send('EHLO local'), throwsA(isA<SmtpClientCommunicationException>()));
    });

    test('timeout applies to the whole response', () async {
      await start((peer, _) async {
        try {
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            peer.write('250-continue\r\n');
          }
          peer.write('250 done\r\n');
        } catch (_) {
          // The client closed the connection.
        }
      }, timeout: const Duration(milliseconds: 500));
      await expectLater(connection.send('EHLO local'), throwsA(isA<TimeoutException>()));
    });

    test('bare response code is accepted', () async {
      await start((peer, _) => peer.write('250\r\n'));
      final response = await connection.send('NOOP');
      expect(response!.responseCode, '250');
      expect(response.responseLines, ['']);
    });
  });

  group('PersistentConnection', () {
    test('validates the message before connecting', () async {
      final server = _ScriptedServer();
      await server.start((_, __, ___) {});
      final connection = PersistentConnection(server.config);
      try {
        final message = _message()
          ..bccRecipients.add('victim@example.com>\r\nRCPT TO:<attacker@example.net');
        await expectLater(connection.send(message), throwsA(isA<SmtpMessageValidationException>()));
        expect(server.connections, 0);
      } finally {
        await connection.close();
        await server.stop();
      }
    });

    test('reconnects after a failed send', () async {
      final server = _ScriptedServer();
      await server.start((peer, line, connection) {
        if (line.startsWith('EHLO')) {
          peer.write('250 localhost\r\n');
        } else if (line.startsWith('MAIL')) {
          peer.write(connection == 1 ? '550 original failure\r\n' : '250 OK\r\n');
        } else if (line.startsWith('RCPT') || line == '.') {
          peer.write('250 OK\r\n');
        } else if (line == 'DATA') {
          peer.write('354 ready\r\n');
        }
      });
      final connection = PersistentConnection(server.config);
      try {
        await expectLater(
            connection.send(_message()),
            throwsA(isA<SmtpClientCommunicationException>()
                .having((e) => e.toString(), 'message', contains('original failure'))));
        await connection.send(_message());
        expect(server.connections, 2);
      } finally {
        await connection.close();
        await server.stop();
      }
    });
  });
}
