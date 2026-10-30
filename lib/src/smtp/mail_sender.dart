import 'dart:async';

import 'package:logging/logging.dart';
import 'validator.dart';

import '../../mailer.dart';
import '../../smtp_server.dart';
import 'connection.dart';
import 'smtp_client.dart' as client;

final Logger _logger = Logger('mailer_sender');

class _MailSendTask {
  // If [message] is `null` close connection.
  Message? message;
  // if `null` connection close was successful.
  late Completer<SendReport?> completer;
}

class PersistentConnection {
  Connection? _connection;

  final mailSendTasksController = StreamController<_MailSendTask>();
  Stream<_MailSendTask> get _mailSendTasks => mailSendTasksController.stream;

  PersistentConnection(SmtpServer smtpServer, {Duration? timeout}) {
    _mailSendTasks.asyncMap<void>((_MailSendTask task) async {
      _logger.finer('New mail sending task.  ${task.message?.subject}');
      try {
        if (task.message == null) {
          // Close connection.
          if (_connection != null) {
            await client.close(_connection);
            _connection = null;
          }
          task.completer.complete(null);
          return;
        }

        _connection ??= await client.connect(smtpServer, timeout);
        var report = await _send(task.message!, _connection!, timeout);
        task.completer.complete(report);
      } catch (e, stackTrace) {
        final failedConnection = _connection;
        _connection = null;
        try {
          await failedConnection?.abort();
        } catch (_) {
          // Cleanup must not replace the original send failure.
        }
        _logger.fine('Completing with error: $e');
        task.completer.completeError(e, stackTrace);
      }
    }).listen((_) {});
  }

  /// Throws following exceptions:
  /// [SmtpClientAuthenticationException],
  /// [SmtpUnsecureException],
  /// [SmtpClientCommunicationException],
  /// [SocketException]     // Connection dropped
  /// [SmtpMessageValidationException]
  /// Please report other exceptions you encounter.
  Future<SendReport> send(Message message) async {
    _validate(message);
    _logger.finer('Adding message to mailSendQueue');
    var mailTask = _MailSendTask()
      ..message = message
      ..completer = Completer();
    mailSendTasksController.add(mailTask);
    return await mailTask.completer.future
        // `null` is only a valid return value for connection close messages.
        .then((value) => ArgumentError.checkNotNull(value));
  }

  /// Throws following exceptions:
  /// [SmtpClientAuthenticationException],
  /// [SmtpUnsecureException],
  /// [SmtpClientCommunicationException],
  /// [SocketException]
  /// Please report other exceptions you encounter.
  Future<void> close() async {
    _logger.finer('Adding "close"-message to mailSendQueue');
    var closeTask = _MailSendTask()..completer = Completer();
    mailSendTasksController.add(closeTask);
    try {
      await closeTask.completer.future;
    } finally {
      await mailSendTasksController.close();
    }
  }
}

/// Throws following exceptions:
/// [SmtpClientAuthenticationException],
/// [SmtpClientCommunicationException],
/// [SocketException]
/// [SmtpMessageValidationException]
/// Please report other exceptions you encounter.
Future<SendReport> send(Message message, SmtpServer smtpServer, {Duration? timeout}) async {
  _validate(message);
  final connection = await client.connect(smtpServer, timeout);
  try {
    final sendReport = await _send(message, connection, timeout);
    return sendReport;
  } finally {
    await client.close(connection);
  }
}

/// Convenience method for testing SmtpServer configuration.
///
/// Throws following exceptions if the configuration is incorrect or there is
/// no internet connection:
/// [SmtpClientAuthenticationException],
/// [SmtpClientCommunicationException],
/// [SocketException]
/// others
Future<void> checkCredentials(SmtpServer smtpServer, {Duration? timeout}) async {
  var connection = await client.connect(smtpServer, timeout);
  await client.close(connection);
}

/// [SmtpMessageValidationException]
void _validate(Message message) {
  var validationProblems = validate(message);
  if (validationProblems.isNotEmpty) {
    _logger.severe('Message validation error: '
        '${validationProblems.map((p) => p.msg).join('|')}');
    throw SmtpMessageValidationException('Invalid message.', validationProblems);
  }
}

/// Connection [connection] must already be connected.
/// Throws following exceptions:
/// [SmtpClientCommunicationException],
/// [SocketException]
/// Please report other exceptions you encounter.
Future<SendReport> _send(Message message, Connection connection, Duration? timeout) async {
  final messageSendStart = DateTime.now();
  DateTime messageSendEnd;
  try {
    await client.sendSingleMessage(message, connection, timeout);
    messageSendEnd = DateTime.now();
  } catch (e) {
    _logger.warning('Could not send mail.', e);
    rethrow;
  }
  // If sending the message was successful we had to open a connection and
  // `connection.connectionOpenStart` can no longer be null.
  return SendReport(message, connection.connectionOpenStart!, messageSendStart, messageSendEnd);
}
