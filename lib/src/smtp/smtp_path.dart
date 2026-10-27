import 'exceptions.dart';

final _controls = RegExp(r'[\x00-\x1F\x7F]');
final _unsafeUnquoted = RegExp(r'[<>"\\\x00-\x20\x7F]');

// Enforce the SMTP path boundary, leaving address policy to the configured
// validator. Quoting is only allowed for a complete local-part at the start.
bool isSafeSmtpMailbox(String address) {
  if (address.isEmpty || _controls.hasMatch(address)) return false;
  if (!address.startsWith('"')) return !_unsafeUnquoted.hasMatch(address);

  for (var i = 1; i < address.length; i++) {
    if (address[i] == r'\') {
      // An escaped quote does not end the local-part.
      i++;
      if (i >= address.length) return false;
    } else if (address[i] == '"') {
      final suffix = address.substring(i + 1);
      return suffix.isEmpty || (suffix.startsWith('@') && !_unsafeUnquoted.hasMatch(suffix));
    }
  }
  return false;
}

/// Serialize one mailbox as an SMTP path independently of user validators.
/// Local-only mailboxes remain available to permissive validators.
String smtpPath(String address) {
  if (!isSafeSmtpMailbox(address)) {
    throw SmtpClientCommunicationException('Invalid SMTP envelope address');
  }
  return '<$address>';
}
