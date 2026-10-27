import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import '../../smtp_server.dart';
import 'exceptions.dart';

import 'capabilities.dart';

/// This class contains all relevant data for one smtp connection/session.
///
/// This includes the socket, smtp-options, but also other objects, relevant
/// for an smtp session, like an input queue.

final _logger = Logger('Connection');
final _invalidCommandCharacter = RegExp(r'[\x00-\x1F\x7F]');
final _responsePrefix = RegExp(r'^[0-9]{3}(?:[ -]|$)');
const _maxResponseLineLength = 8192;
const _maxResponseLines = 100;
const _maxResponseLength = 65536;

class ServerResponse {
  final String responseCode;

  /// Every line received from the server is one entry in the message list.
  final List<String> responseLines;

  ServerResponse(this.responseCode, this.responseLines);
}

class Connection {
  final SmtpServer server;
  final Duration timeout;
  DateTime? _connectionOpenStart;

  DateTime? get connectionOpenStart => _connectionOpenStart;

  late Capabilities capabilities;

  // Done with close function.
  // ignore: close_sinks
  Socket? _socket;
  StreamQueue<String>? _socketIn;

  Connection(this.server, {Duration? timeout})
      // ignore: unnecessary_this
      : this.timeout = timeout ?? const Duration(seconds: 60);

  bool get isSecure => _socket != null && _socket is SecureSocket;

  Future sendStream(Stream<List<int>> s) => _socket!.addStream(s);

  /// Returns the next message from server.  An exception is thrown if
  /// [acceptedRespCodes] is not empty and the response code from the server
  /// does not start with any of the strings in [acceptedRespCodes];
  Future<ServerResponse?> send(String command,
      {List<String>? acceptedRespCodes = const ['2'],
      String? expect,
      bool waitForResponse = true,
      bool private = false}) async {
    if (_invalidCommandCharacter.hasMatch(command)) {
      throw SmtpClientCommunicationException('SMTP command contains a control character');
    }
    // Send the new command.
    if (private) {
      _logger.fine('> *******');
    } else {
      _logger.fine('> $command');
    }
    if (command.isNotEmpty) {
      _socket!.write('$command\r\n');
    }

    if (!waitForResponse) {
      // Even though we don't wait for a response, we still wait until the
      // command has been sent.
      await _socket!.flush().timeout(timeout);
      return null;
    }

    final messages = <String>[];
    String responseCode;

    late String currentLine;
    var responseLines = 0;
    var responseLength = 0;
    final responseTimer = Stopwatch()..start();

    // A response from the server always has a space as the 4th character
    // for the _last_ line of a response.
    // Multi-line responses have '-' as 4th character except for the last
    // line.
    while (true) {
      final remaining = timeout - responseTimer.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('SMTP response timed out', timeout);
      }
      var hasNext = await _socketIn!.hasNext.timeout(remaining);
      if (!hasNext) {
        throw SmtpClientCommunicationException(
            'Socket was closed even though a response was expected.');
      }

      // Let's timeout if we don't receive anything from the other side.
      // This is possible if we for instance connect to an SSL port where the
      // socket connection succeeds, but we never receive anything because we
      // are stuck in the SSL negotiation process.
      final nextRemaining = timeout - responseTimer.elapsed;
      if (nextRemaining <= Duration.zero) {
        throw TimeoutException('SMTP response timed out', timeout);
      }
      currentLine = await _socketIn!.next.timeout(nextRemaining);

      if (currentLine.length < 3 || !_responsePrefix.hasMatch(currentLine)) {
        throw SmtpClientCommunicationException('Malformed SMTP response');
      }
      responseLines++;
      responseLength += currentLine.length;
      if (responseLines > _maxResponseLines || responseLength > _maxResponseLength) {
        throw SmtpClientCommunicationException('SMTP response is too long');
      }

      messages.add(currentLine.length == 3 ? '' : currentLine.substring(4));
      if (currentLine.length == 3 || currentLine[3] == ' ') break;
    }

    responseCode = currentLine.substring(0, 3);

    var mString = messages.map((m) => '< $responseCode $m').join('\n');
    final responseForLogs = private ? '< $responseCode [redacted]' : mString;
    _logger.fine(responseForLogs);

    if (acceptedRespCodes != null &&
        acceptedRespCodes.isNotEmpty &&
        !acceptedRespCodes.any((start) => responseCode.startsWith(start))) {
      var msg = 'After sending ${private ? '[redacted]' : command}, '
          'response did not start with any of: $acceptedRespCodes.';
      msg += '\nResponse from server: $responseForLogs';
      _logger.warning(msg);
      throw SmtpClientCommunicationException(msg);
    }

    return ServerResponse(responseCode, private ? ['[redacted]'] : messages);
  }

  /// Upgrades the connection to use TLS.
  Future<void> upgradeConnection() async {
    // SecureSocket.secure suggests to call socketSubscription.pause().
    // A StreamQueue always pauses unless we explicitly call next().
    // So we don't need to call pause() ourselves.
    _socket =
        await SecureSocket.secure(_socket!, onBadCertificate: (_) => server.ignoreBadCertificate);
    _setSocketIn();
  }

  /// Initializes a connection to the given server.
  Future<void> connect() async {
    _connectionOpenStart = DateTime.now();
    _logger.finer('Connecting to ${server.host} at port ${server.port}.');

    // Secured connection was demanded by the user.
    if (server.ssl) {
      _socket = await SecureSocket.connect(server.host, server.port,
          onBadCertificate: (_) => server.ignoreBadCertificate, timeout: timeout);
    } else {
      _socket = await Socket.connect(server.host, server.port, timeout: timeout);
    }
    _socket!.timeout(timeout);

    _setSocketIn();
  }

  Future<void> close() async {
    if (_socket != null) await _socket!.close();
    if (_socketIn != null) await _socketIn!.cancel(immediate: true);
  }

  /// Abandon a failed transaction without flushing data or sending QUIT.
  Future<void> abort() async {
    _socket?.destroy();
    if (_socketIn != null) await _socketIn!.cancel(immediate: true);
  }

  void _setSocketIn() {
    if (_socketIn != null) {
      _socketIn!.cancel();
    }
    _socketIn = StreamQueue<String>(_boundedLines(_socket!));
  }

  void verifySecuredConnection() {
    if (!server.allowInsecure && !isSecure) {
      _socket!.close();
      throw SmtpUnsecureException('Aborting because connection is not secure');
    }
  }
}

Stream<String> _boundedLines(Stream<List<int>> input) async* {
  var line = StringBuffer();
  await for (final chunk in utf8.decoder.bind(input)) {
    for (final unit in chunk.codeUnits) {
      if (unit == 10) {
        var value = line.toString();
        if (value.endsWith('\r')) value = value.substring(0, value.length - 1);
        yield value;
        line = StringBuffer();
      } else {
        if (line.length >= _maxResponseLineLength) {
          throw SmtpClientCommunicationException('SMTP response line is too long');
        }
        line.writeCharCode(unit);
      }
    }
  }
  if (line.isNotEmpty) yield line.toString();
}
