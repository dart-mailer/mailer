import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/src/mime/mime.dart';
import 'package:mailer/src/smtp/capabilities.dart';
import 'package:mailer/src/smtp/connection.dart';
import 'package:mailer/src/smtp/smtp_client.dart' as client;
import 'package:mailer/src/smtp/validator.dart';
import 'package:mailer/smtp_server.dart';
import 'package:test/test.dart';

Message _message() => Message()
  ..from = 'sender@example.com'
  ..recipients.add('recipient@example.com')
  ..text = 'hello';

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
  Future<void> sendStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }
}

class _UnsafeEncodedAddress extends Address {
  const _UnsafeEncodedAddress() : super('safe@example.com');

  @override
  String get encodedAddress => 'unsafe@example.com\r\nx-injected: yes';
}

class _Server {
  late ServerSocket listener;
  final peers = <Socket>[];
  final commands = <String>[];
  int connections = 0;

  SmtpServer get config => SmtpServer('127.0.0.1', port: listener.port, allowInsecure: true);

  Future<void> start(void Function(Socket, String, int) respond, {bool greeting = true}) async {
    listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    listener.listen((peer) {
      peers.add(peer);
      final number = ++connections;
      if (greeting) peer.write('220 ready\r\n');
      utf8.decoder.bind(peer).transform(const LineSplitter()).listen((line) {
        commands.add(line);
        respond(peer, line, number);
      }, onError: (Object _) {});
    });
  }

  Future<void> close() async {
    for (final peer in peers) {
      peer.destroy();
    }
    await listener.close();
  }
}

void main() {
  test('default validator requires one domain after a quoted local-part', () {
    for (final address in [r'"local\"@part"', '"local"@', '"local"@example@com']) {
      expect(validate(_message()..envelopeFrom = address).map((p) => p.code), contains('ENV_FROM'),
          reason: address);
    }
  });

  test('envelope safety preserves harmless existing address syntax', () async {
    for (final address in [
      'user..name@example.com',
      '.user@example.com',
      'user@under_score.example',
      'user@example.com.',
      'user(comment)@example.com',
    ]) {
      final message = _message()..envelopeFrom = address;
      expect(validate(message), isEmpty, reason: address);
      final connection = _RecordingConnection();
      await client.sendSingleMessage(message, connection, null);
      expect(connection.commands.first, 'MAIL FROM:<$address>');
    }
  });

  test('encoded header overrides are checked before SMTP', () {
    final message = _message()..headers['reply-to'] = const _UnsafeEncodedAddress();
    expect(validate(message).map((p) => p.code), contains('INVALID_HEADER'));
  });

  const attack = 'sender@example.com> RET=HDRS ENVID=owned';
  final setters = <String, void Function(Message, String)>{
    'envelopeFrom': (m, a) => m.envelopeFrom = a,
    'envelopeTos': (m, a) => m.envelopeTos = [a],
    'from': (m, a) => m.from = a,
    'to': (m, a) => m.recipients.add(a),
    'cc': (m, a) => m.ccRecipients.add(a),
    'bcc': (m, a) => m.bccRecipients.add(a),
  };
  for (final entry in setters.entries) {
    for (final permissive in [false, true]) {
      test('${entry.key} rejects envelope options (permissive=$permissive)', () async {
        final message = _message();
        if (permissive) message.validator = const PermissiveAddressValidator();
        entry.value(message, attack);
        expect(validate(message), isNotEmpty);
        final connection = _RecordingConnection();
        await expectLater(client.sendSingleMessage(message, connection, null),
            throwsA(isA<SmtpClientCommunicationException>()));
        expect(connection.commands, isEmpty);
      });
    }
  }

  for (final address in [
    '"quoted>name"@example.com',
    r'"quoted\">name"@example.com',
    '"quoted@name"@example.com'
  ]) {
    test('quoted local-part is serialized intact: $address', () async {
      final message = _message()
        ..envelopeFrom = address
        ..envelopeTos = [address];
      expect(validate(message), isEmpty);
      final connection = _RecordingConnection();
      await client.sendSingleMessage(message, connection, null);
      expect(connection.commands.take(2), ['MAIL FROM:<$address>', 'RCPT TO:<$address>']);
    });
  }

  for (final address in [
    'a@example.com\r\nx-injected: yes',
    'a@example.com\nx-injected: yes',
    'a@example.com\r x-injected: yes',
  ]) {
    test('unsafe address header is rejected before connecting: ${jsonEncode(address)}', () async {
      final message = _message()..headers['reply-to'] = Address(address);
      expect(validate(message).map((p) => p.code), contains('INVALID_HEADER'));
      final server = _Server();
      await server.start((_, __, ___) {});
      final persistent = PersistentConnection(server.config);
      try {
        await expectLater(
            send(message, server.config), throwsA(isA<SmtpMessageValidationException>()));
        await expectLater(persistent.send(message), throwsA(isA<SmtpMessageValidationException>()));
        expect(server.connections, 0);
        expect(server.commands, isEmpty);
      } finally {
        await persistent.close();
        await server.close();
      }
    });
  }

  for (final address in ['bob@example.com\t(Support)', 'bob@example.com\r\n (Support)']) {
    test('legal header CFWS survives validation and rendering: ${jsonEncode(address)}', () async {
      final message = _message()..headers['reply-to'] = Address(address);
      expect(validate(message), isEmpty);
      final bytes =
          await MimeMessage(message).data(const Capabilities()).expand((part) => part).toList();
      expect(utf8.decode(bytes), contains('reply-to: ${address.replaceAll('\r\n', '')}\r\n'));
    });
  }

  test('private final response retains code but redacts reflected credentials', () async {
    final server = _Server();
    await server.start((peer, line, _) => peer.write('535 rejected $line\r\n'), greeting: false);
    final connection = Connection(server.config);
    try {
      await connection.connect();
      final response = await connection.send('c2Vuc2l0aXZl', acceptedRespCodes: [], private: true);
      expect(response!.responseCode, '535');
      expect(response.responseLines, ['[redacted]']);
    } finally {
      await connection.close();
      await server.close();
    }
  });

  test('final AUTH rejection keeps credentials out of exception and logs', () async {
    final server = _Server();
    await server.start((peer, line, _) {
      if (line.startsWith('EHLO')) {
        peer.write('250-localhost\r\n250 AUTH PLAIN\r\n');
      } else if (line == 'AUTH PLAIN') {
        peer.write('334 continue\r\n');
      } else {
        peer.write('535 rejected $line\r\n');
      }
    });
    final logs = <String>[];
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen((record) => logs.add(record.toString()));
    final connection = PersistentConnection(SmtpServer('127.0.0.1',
        port: server.listener.port, allowInsecure: true, username: 'user', password: 'sensitive'));
    try {
      final secret = base64.encode(utf8.encode('\u0000user\u0000sensitive'));
      await expectLater(
          connection.send(_message()),
          throwsA(isA<SmtpClientAuthenticationException>()
              .having((e) => e.toString(), 'exception', isNot(contains(secret)))));
      expect(logs.join('\n'), isNot(contains(secret)));
      expect(logs.join('\n'), isNot(contains('sensitive')));
    } finally {
      await connection.close();
      await subscription.cancel();
      Logger.root.level = previousLevel;
      await server.close();
    }
  });

  test('persistent send reconnects after failure and preserves original error', () async {
    final server = _Server();
    await server.start((peer, line, number) {
      if (line.startsWith('EHLO')) {
        peer.write('250 localhost\r\n');
      } else if (line.startsWith('MAIL')) {
        peer.write(number == 1 ? '550 original failure\r\n' : '250 OK\r\n');
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
              .having((e) => e.toString(), 'original failure', contains('original failure'))));
      await connection.send(_message());
      expect(server.connections, 2);
      expect(server.commands.where((line) => line.startsWith('MAIL')), hasLength(2));
    } finally {
      await connection.close();
      await server.close();
    }
  });

  test('bare three digit SMTP reply is accepted', () async {
    final server = _Server();
    await server.start((peer, _, __) => peer.write('250\r\n'), greeting: false);
    final connection = Connection(server.config);
    try {
      await connection.connect();
      final response = await connection.send('NOOP');
      expect(response!.responseCode, '250');
      expect(response.responseLines, ['']);
    } finally {
      await connection.close();
      await server.close();
    }
  });
}
