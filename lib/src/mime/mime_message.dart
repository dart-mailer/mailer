part of 'mime.dart';

class MimeMessage {
  final Message? _message;
  late Part _content;
  late Iterable<Header> _headers;

  static final _nonAscii = RegExp(r'[^\x00-\x7F]');

  // Possibly throws.
  MimeMessage(this._message) {
    _headers = _buildHeaders(_message!);
    _content = MultipartMixed(_message!, _headers);
  }

  /// The envelope recipients.
  ///
  /// Domains are converted to punycode (IDNA), local parts are kept as is.
  Iterable<String?> get envelopeTos {
    // All recipients.
    Iterable<String?> envelopeTos = _message!.envelopeTos ?? [];

    if (envelopeTos.isEmpty) {
      envelopeTos = [
        ..._message!.recipientsAsAddresses,
        ..._message!.ccsAsAddresses,
        ..._message!.bccsAsAddresses
      ].map((a) => a.mailAddress);
    }
    return envelopeTos.map((a) => a == null ? null : Address(a).encodedAddress);
  }

  /// The envelope sender.
  ///
  /// The domain is converted to punycode (IDNA), the local part is kept as is.
  String get envelopeFrom =>
      Address(_message!.envelopeFrom ?? _message!.fromAsAddress.mailAddress).encodedAddress;

  /// Whether the message can only be transported with SMTPUTF8 (rfc6531).
  ///
  /// This is only the case if an address (envelope or header) contains a
  /// non-ASCII local part.  Domains are converted to punycode and all other
  /// headers can be encoded (rfc2047).
  /// SMTPUTF8 must only be used if necessary, as the message is bounced as
  /// soon as one server on the route doesn't support it.
  bool get requiresSmtpUtf8 {
    final headerAddresses = _headers.expand((header) {
      if (header is AddressHeader) return [header._address];
      if (header is AddressListHeader) return header._addresses;
      return const <Address>[];
    }).map((a) => a.encodedAddress);
    return [envelopeFrom, ...envelopeTos.whereType<String>(), ...headerAddresses]
        .any(_nonAscii.hasMatch);
  }

  Stream<List<int>> data(Capabilities capabilities) =>
      _content.out(RenderContext(capabilities)).map((s) {
        if (s is String) {
          return convert.utf8.encode(s);
        }
        if (s is List<int>) {
          return s;
        }
        throw StateError('Did not expect ${s.runtimeType} in Part stream');
      });
}

class InvalidHeaderException implements Exception {
  String message;

  InvalidHeaderException(this.message);
}
