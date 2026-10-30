import 'package:meta/meta.dart';

@visibleForTesting
Capabilities capabilitiesForTesting(
    {bool startTls = false,
    bool smtpUtf8 = false,
    bool authPlain = true,
    bool authLogin = false,
    bool authXoauth2 = false,
    bool chunking = false,
    bool binaryMime = false,
    List<String> all = const <String>[]}) {
  return Capabilities._values(
      startTls, smtpUtf8, authPlain, authLogin, authXoauth2, chunking, binaryMime, all);
}

class Capabilities {
  final bool startTls;
  final bool smtpUtf8;
  final bool authPlain;
  final bool authLogin;
  final bool authXoauth2;
  final bool chunking;
  final bool binaryMime;
  final List<String> all;

  const Capabilities()
      : startTls = false,
        smtpUtf8 = false,
        authPlain = true,
        authLogin = false,
        authXoauth2 = false,
        chunking = false,
        binaryMime = false,
        all = const <String>[];

  const Capabilities._values(this.startTls, this.smtpUtf8, this.authPlain, this.authLogin,
      this.authXoauth2, this.chunking, this.binaryMime, this.all);

  factory Capabilities.fromResponse(Iterable<String> ehloMessage) {
    final capabilities = List<String>.unmodifiable(ehloMessage.map((m) => m.toUpperCase()));

    var startTls = false;
    var smtpUtf8 = false;
    var plain = false;
    var login = false;
    var xoauth2 = false;
    var chunking = false;
    var binaryMime = false;

    for (var cap in capabilities) {
      if (cap.contains('STARTTLS')) {
        startTls = true;
      } else if (cap.contains('SMTPUTF8')) {
        smtpUtf8 = true;
      } else if (cap.startsWith('AUTH ')) {
        var authMethods = cap.split(' ').skip(1); // First is 'AUTH'
        plain = authMethods.contains('PLAIN');
        login = authMethods.contains('LOGIN');
        xoauth2 = authMethods.contains('XOAUTH2');
      } else if (cap.contains('CHUNKING')) {
        chunking = true;
      } else if (cap.contains('BINARYMIME')) {
        binaryMime = true;
      }
    }

    // rfc3030 3: BINARYMIME may only be used together with CHUNKING (BDAT).
    return Capabilities._values(
        startTls, smtpUtf8, plain, login, xoauth2, chunking, binaryMime && chunking, capabilities);
  }
}
