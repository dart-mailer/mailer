import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import '../../smtp_server.dart';

import '../core/message.dart';
import 'capabilities.dart';
import 'connection.dart';
import 'exceptions.dart';
import '../mime/mime.dart';
import 'buffering_stream_transformer.dart';
import 'smtp_path.dart';

/// Returns if ehlo was successful.
Future<bool> _doEhlo(Connection c, String clientName) async {
  var respEhlo = await (c.send('EHLO $clientName', acceptedRespCodes: null));

  if (!(respEhlo == null || respEhlo.responseCode.startsWith('2'))) {
    return false;
  }

  var capabilities = Capabilities.fromResponse(respEhlo!.responseLines);

  if (!capabilities.startTls || c.isSecure) {
    c.capabilities = capabilities;
    return true;
  }

  // Use a secure socket.  Server announced STARTTLS.
  // The server supports TLS and we haven't switched to it yet,
  // so let's do it.
  var tlsResp = await c.send('STARTTLS', acceptedRespCodes: null);
  if (tlsResp == null || !tlsResp.responseCode.startsWith('2')) {
    // Even though server announced STARTTLS, it now chickens out.
    return false;
  }

  // Replace _socket with an encrypted version.
  await c.upgradeConnection();

  // Restart EHLO process.  This time on a secure connection.
  return _doEhlo(c, clientName);
}

Future<void> _doEhloHelo(Connection c, {String? clientName}) async {
  if (clientName == null || clientName.trim().isEmpty) {
    clientName = Platform.localHostname;
  }

  final ehloSuccessful = await _doEhlo(c, clientName);

  if (ehloSuccessful) {
    return;
  }

  // EHLO not accepted.  Let's try HELO.
  await c.send('HELO $clientName');
  c.capabilities = Capabilities();
}

Future<ServerResponse> _doAuthLogin(Connection c) async {
  var username = c.server.username!;
  var password = c.server.password!;

  // 'Username:' in base64 is: VXN...
  await c.send('AUTH LOGIN', acceptedRespCodes: ['334'], expect: 'VXNlcm5hbWU6');
  // 'Password:' in base64 is: UGF...
  await c.send(convert.base64.encode(username.codeUnits),
      acceptedRespCodes: ['334'], expect: 'UGFzc3dvcmQ6', private: true);
  var loginResp =
      await c.send(convert.base64.encode(password.codeUnits), acceptedRespCodes: [], private: true);

  return loginResp!;
}

Future<ServerResponse> _doAuthPlain(Connection c) async {
  var digest = _getPlainDigest(c.server.username!, c.server.password!);

  await c.send('AUTH PLAIN', acceptedRespCodes: ['334']);
  var loginResp = await c.send(digest, acceptedRespCodes: [], private: true);

  return loginResp!;
}

String _getPlainDigest(String username, String password) {
  var u = convert.utf8.encode(username);
  var p = convert.utf8.encode(password);
  var a = <int>[0];
  a.addAll(u);
  a.add(0);
  a.addAll(p);
  return convert.base64.encoder.convert(a);
}

Future<ServerResponse> _doAuthXoauth2(Connection c) async {
  var token = c.server.xoauth2Token;

  // See https://developers.google.com/gmail/imap/xoauth2-protocol
  final loginResp = await c.send('AUTH XOAUTH2 $token', acceptedRespCodes: [], private: true);
  return loginResp!;
}

Future<void> _doAuthentication(Connection c) async {
  ServerResponse? loginResp;

  if (c.server.username != null && c.server.password != null) {
    if (c.capabilities.authLogin) {
      loginResp = await _doAuthLogin(c);
    } else if (c.capabilities.authPlain) {
      loginResp = await _doAuthPlain(c);
    } else {
      throw SmtpClientCommunicationException(
          'The server does not support LOGIN or PLAIN authentication method.');
    }
  } else if (c.server.xoauth2Token != null) {
    if (c.capabilities.authXoauth2) {
      loginResp = await _doAuthXoauth2(c);
    } else {
      throw SmtpClientCommunicationException(
          'The server does not support XOAUTH2 authentication method.');
    }
  }

  if (loginResp != null && !loginResp.responseCode.startsWith('2')) {
    throw SmtpClientAuthenticationException(
      'Authentication Failed (code: ${loginResp.responseCode}), response:\n${loginResp.responseLines.map((m) => '< $m').join('\n')}',
    );
  }
}

Future<Connection> connect(SmtpServer smtpServer, Duration? timeout) async {
  final c = Connection(smtpServer, timeout: timeout);

  try {
    await c.connect();

    try {
      // Greeting (Don't send anything.  We first wait for a 2xx message.)
      await c.send('');
    } on TimeoutException {
      if (!c.isSecure) {
        throw SmtpNoGreetingException('Timed out while waiting for greeting (try ssl).');
      } else {
        throw SmtpNoGreetingException('Timed out while waiting for greeting.');
      }
    }

    // EHLO / HELO
    await _doEhloHelo(c);

    c.verifySecuredConnection();

    // Authenticate
    await _doAuthentication(c);
    return c;
  } catch (e) {
    await c.close();
    rethrow;
  }
}

Future<void> close(Connection? connection) async {
  if (connection == null) {
    return;
  }
  try {
    await connection.send('QUIT', waitForResponse: false);
  } finally {
    await connection.close();
  }
}

/// Connection [c] must have been opened before.
/// The message should be validated before passing it to this function.
/// This function does not close the connection [c].
///
/// Throws following exceptions:
/// [SmtpClientAuthenticationException],
/// [SmtpClientCommunicationException],
/// [SmtpUnsecureException],
/// [SocketException],
Future<void> sendSingleMessage(Message? message, Connection c, Duration? timeout) async {
  var irMessage = MimeMessage(message);
  // Validate every path before issuing even the first envelope command.
  final envelopeFrom = smtpPath(irMessage.envelopeFrom, allowNull: true);
  final envelopeTos = irMessage.envelopeTos.map((address) => smtpPath(address!)).toList();

  var capabilities = c.capabilities;

  // Tell the server the envelope from address (might be different to the
  // 'From: ' header!)
  var smtpUtf8 = capabilities.smtpUtf8;
  await c.send('MAIL FROM:$envelopeFrom${smtpUtf8 ? ' SMTPUTF8' : ''}');

  // Give the server all recipients.
  // TODO what if only one address fails?
  await Future.forEach(envelopeTos, (String recipient) => c.send('RCPT TO:$recipient'));

  // Finally send the actual mail.
  if (capabilities.chunking) {
    // STREAMING via BDAT
    await for (var chunk
        in irMessage.data(capabilities).transform(BufferingStreamTransformer(64 * 1024))) {
      await c.send('BDAT ${chunk.length}', acceptedRespCodes: [], waitForResponse: false);
      await c.sendStream(Stream.value(chunk));
      await c.send('', acceptedRespCodes: ['2']);
    }
    await c.send('BDAT 0 LAST', acceptedRespCodes: ['2']);
  } else {
    // DATA command
    await c.send('DATA', acceptedRespCodes: ['2', '3']);
    await c.sendStream(irMessage.data(capabilities));
    await c.send('.', acceptedRespCodes: ['2', '3']);
  }
}
