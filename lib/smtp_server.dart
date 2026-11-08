export 'smtp_server/amazon.dart';
export 'smtp_server/brevo.dart';
export 'smtp_server/gmail.dart';
export 'smtp_server/hotmail.dart';
export 'smtp_server/mailgun.dart';
export 'smtp_server/qq.dart';
export 'smtp_server/sendgrid.dart';
export 'smtp_server/yahoo.dart';
export 'smtp_server/yandex.dart';
export 'smtp_server/zoho.dart';

class SmtpServer {
  final String host;
  final int port;
  final bool ignoreBadCertificate;

  /// Connect to the smtp server over a secure ssl connection.
  /// Setting this option to false does NOT mean, that mails will be sent over
  /// unencrypted connections!
  /// SSL for smtp servers is uncommon!
  /// Usually this library will connect to the server over an insecure
  /// connection first and use the smtp command `starttls` to upgrade the
  /// connection to a secure one.  If the server doesn't support
  /// `starttls` we will abort if `allowInsecure` is false.
  final bool ssl;

  /// This library will always use secure connections if the server supports it,
  /// and will abort if unsuccessful unless `allowInsecure` is `true`.
  final bool allowInsecure;
  final String? username;
  final String? password;
  final String? xoauth2Token;

  /// Send text and attachments unencoded (rfc3030 BINARYMIME), if the server
  /// supports it.
  ///
  /// This reduces the size of messages with attachments by about 25%, but only
  /// between this client and the server.
  ///
  /// Only enable this if the server converts binary messages (to base64) when it
  /// relays them to a server without BINARYMIME, or if every server on the
  /// route supports BINARYMIME.  Few servers support BINARYMIME (e.g. Microsoft
  /// Exchange does, Gmail, Postfix and Exim don't), and rfc3030 allows relays
  /// to bounce binary messages instead of converting them.
  ///
  /// If the message is DKIM signed before it is converted, the conversion
  /// breaks the signature.  The message may then be classified as spam or
  /// rejected, without a bounce.
  final bool useBinaryMime;

  SmtpServer(this.host,
      {this.port = 587,
      this.ignoreBadCertificate = false,
      this.ssl = false,
      this.allowInsecure = false,
      this.username,
      this.password,
      this.xoauth2Token,
      this.useBinaryMime = false});
}
