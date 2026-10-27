part of 'mime.dart';

abstract class Header extends _MimeOutput {
  @override
  Stream<String> out(RenderContext renderContext) => Stream.value(render(renderContext));

  String render(RenderContext renderContext);

  final String _name;

  static const _b64Length = 12; // "=?utf-8?B?".length + "?=".length
  static final _nonAscii = RegExp(r'[^\x20-\x7E]');

  String _buildValueWithParms(String value, RenderContext renderContext,
      [Map<String, String>? parms]) {
    var buffer = StringBuffer();
    if (Header._shouldUseBase64(value, renderContext)) {
      buffer.write('$_name: ');
      buffer.write(_encodeBase64(value));
    } else {
      buffer.write('$_name: $value');
    }
    if (parms != null) {
      for (var entry in parms.entries) {
        if (Header._shouldUseBase64(entry.value, renderContext)) {
          buffer.write('; ${entry.key}="');
          buffer.write(_encodeBase64(entry.value));
          buffer.write('"');
        } else {
          final escaped = entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
          buffer.write('; ${entry.key}="$escaped"');
        }
      }
    }
    buffer.write(eol);
    return buffer.toString();
  }

  /// Outputs the given [addresses].
  String _buildAddressesValue(Iterable<Address> addresses, RenderContext renderContext) {
    var buffer = StringBuffer();
    buffer.write('$_name: ');

    int len = 2; //2 = _$commaSpace
    var second = false;
    for (final address in addresses) {
      final name = address.sanitizedName, mAddr = _safeHeaderAddress(address);
      var addrLen = mAddr.length;
      if (name != null) {
        addrLen += name.length + 3;
      } //not accurate but good enough

      if (second) {
        if (len + addrLen > maxEncodedLength) {
          len = 2;
          buffer.write(', $eol ');
        } else {
          buffer.write(', ');
        }
      } else {
        second = true;
      }

      if (name == null) {
        buffer.write(mAddr);
      } else {
        if (_shouldUseBase64(name, renderContext)) {
          buffer.write(_encodeBase64(name));
          buffer.write(' <$mAddr>');
        } else {
          buffer.write('$name <$mAddr>');
        }
      }

      len += addrLen;
    }

    buffer.write(eol);
    return buffer.toString();
  }

  // Outputs the given [value] encoded as base64.
  static String _encodeBase64(String value) {
    // Encode with base64.
    var availableLengthForBase64 = maxEncodedLength - _b64Length;

    // Length after base64: ceil(n / 3) * 4
    var lengthBeforeBase64 = (availableLengthForBase64 ~/ 4) * 3;
    var availableLength = lengthBeforeBase64;

    // At least 10 chars (random length).
    if (availableLength < 10) availableLength = 10;

    var buffer = StringBuffer();
    var first = true;
    for (var d in split(convert.utf8.encode(value), availableLength)) {
      if (!first) buffer.write('$eol ');
      buffer.write('=?utf-8?B?${convert.base64.encode(d)}?=');
      first = false;
    }
    return buffer.toString();
  }

  static bool _shouldUseBase64(String value, RenderContext renderContext) {
    // If we have a maxLineLength is it the length of utf8 characters or
    // the length of utf8 bytes?
    // Just to be safe we'll check the bytes.

    // Optimization: if usage of 4 bytes per char is still not exceeding
    // maxLineLength, we don't need to check the byte length.
    if (value.length * 4 > maxLineLength) {
      var byteLength = convert.utf8.encode(value).length;
      if (byteLength > maxLineLength) return true;
    }

    return (!isPrintableRegExp.hasMatch(value) ||
        // Make sure that text which looks like an encoded text is encoded.
        value.contains('=?') ||
        (!renderContext.capabilities.smtpUtf8 && value.contains(_nonAscii)));
  }

  Header(this._name) {
    if (!RegExp(r'^[\x21-\x39\x3B-\x7E]+$').hasMatch(_name)) {
      throw InvalidHeaderException('Invalid header name');
    }
  }
}

class TextHeader extends Header {
  final String value;
  final Map<String, String>? parameters;

  TextHeader(super.name, this.value, [this.parameters = const {}]);

  @override
  String render(RenderContext renderContext) =>
      _buildValueWithParms(value, renderContext, parameters);
}

class AddressHeader extends Header {
  final Address _address;

  AddressHeader(super.name, this._address) {
    _safeHeaderAddress(_address);
  }

  @override
  String render(RenderContext renderContext) => _buildAddressesValue([_address], renderContext);
}

class AddressListHeader extends Header {
  final Iterable<Address> _addresses;

  AddressListHeader(super.name, this._addresses) {
    for (final address in _addresses) {
      _safeHeaderAddress(address);
    }
  }

  @override
  String render(RenderContext renderContext) => _buildAddressesValue(_addresses, renderContext);
}

// Header folding is legal only at CRLF followed by whitespace. Unfold it
// before output, retaining legal HT in CFWS and rejecting all other controls.
String _safeHeaderAddress(Address address) {
  final value = address.encodedAddress.replaceAll(RegExp(r'\r\n(?=[ \t])'), '');
  if (RegExp(r'[\x00-\x08\x0A-\x1F\x7F]').hasMatch(value)) {
    throw InvalidHeaderException('Invalid address in header');
  }
  return value;
}

class ContentTypeHeader extends Header {
  final String _boundary;
  final MultipartType _multipartType;

  ContentTypeHeader(String boundary, MultipartType multipartType, {String name = 'content-type'})
      : _boundary = boundary,
        _multipartType = multipartType,
        super(name);

  @override
  String render(RenderContext renderContext) =>
      '$_name: multipart/${_multipartType.name};boundary="$_boundary"$eol';
}

class DateHeader extends Header {
  final DateTime _dateTime;

  static final DateFormat _dateFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss +0000', 'en_US');

  DateHeader(super.name, this._dateTime);

  @override
  String render(RenderContext renderContext) =>
      '$_name: ${_dateFormat.format(_dateTime.toUtc())}$eol';
}

Iterable<Header> _buildHeaders(Message message) {
  const noCustom = ['content-type', 'mime-version'];

  final headers = <Header>[];
  var msgHeader = message.headers;

  var msgHeaderNames = <String>{};

  // Add all custom headers which are not in [noCustom].
  msgHeader.forEach((name, value) {
    name = name.toLowerCase();
    msgHeaderNames.add(name);
    if (noCustom.contains(name)) return;

    if (value is String && value.contains('@')) {
      headers.add(AddressHeader(name, Address(value)));
    } else if (value is String) {
      headers.add(TextHeader(name, value));
    } else if (value is DateTime) {
      headers.add(DateHeader(name, value));
    } else if (value is Address) {
      headers.add(AddressHeader(name, value));
    } else if (value is Iterable<Address>) {
      headers.add(AddressListHeader(name, value));
    } else if (value is Iterable<String> && value.every((s) => (s).contains('@'))) {
      headers.add(AddressListHeader(name, value.map((a) => Address(a))));
    } else {
      throw InvalidHeaderException('Type of value for $name is invalid');
    }
  });

  if (!msgHeaderNames.contains('subject') && message.subject != null) {
    headers.add(TextHeader('subject', message.subject!));
  }

  if (!msgHeaderNames.contains('from')) {
    headers.add(AddressHeader('from', message.fromAsAddress));
  }

  if (!msgHeaderNames.contains('to')) {
    var tos = message.recipientsAsAddresses;
    if (tos.isNotEmpty) headers.add(AddressListHeader('to', tos));
  }

  if (!msgHeaderNames.contains('cc')) {
    var ccs = message.ccsAsAddresses;
    if (ccs.isNotEmpty) headers.add(AddressListHeader('cc', ccs));
  }

  if (!msgHeaderNames.contains('date')) {
    headers.add(DateHeader(
        'date',
        message.headers['date'] is DateTime
            ? message.headers['date'] as DateTime
            : DateTime.now()));
  }

  if (!msgHeaderNames.contains('x-mailer')) {
    headers.add(TextHeader('x-mailer', 'Dart Mailer library'));
  }

  headers.add(TextHeader('mime-version', '1.0'));

  return headers;
}

class DynamicHeader extends Header {
  final String Function(RenderContext) _resolver;
  DynamicHeader(super.name, this._resolver);

  @override
  String render(RenderContext info) => '$_name: ${_resolver(info)}$eol';
}
