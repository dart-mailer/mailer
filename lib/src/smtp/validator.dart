import '../core/address.dart';
import '../core/address_validator.dart';
import '../core/message.dart';
import '../core/problem.dart';
import '../mime/mime.dart';
import '../utils.dart';
import 'smtp_path.dart';

bool _printableCharsOnly(String s) {
  return isPrintableRegExp.hasMatch(s);
}

/// [addressIn] can either be an [Address] or String.
bool _validAddress(dynamic addressIn, AddressValidator? validator, {bool isEnvelope = false}) {
  if (addressIn == null) return false;

  Address address;
  if (addressIn is Address) {
    address = addressIn;
  } else {
    address = Address(addressIn as String);
  }

  if (isEnvelope && !isSafeSmtpMailbox(address.mailAddress)) {
    return false;
  }

  if (validator != null) {
    return validator.validate(address);
  }

  return _validMailAddress(address.mailAddress);
}

bool _validMailAddress(String ma) {
  // A quoted local-part may contain @, so locate the domain after its closing quote.
  if (ma.startsWith('"')) {
    final closingQuote = ma.lastIndexOf('"');
    if (closingQuote == 0 || closingQuote >= ma.length - 2 || ma[closingQuote + 1] != '@') {
      return false;
    }
    final domain = ma.substring(closingQuote + 2);
    return !domain.contains('@') && _printableCharsOnly(domain);
  }
  var split = ma.split('@');
  return split.length == 2 && split.every((part) => part.isNotEmpty && _printableCharsOnly(part));
}

List<Problem> validate(Message message) {
  var res = <Problem>[];

  void validate(bool isValid, String code, String msg) {
    if (!isValid) {
      res.add(Problem(code, msg));
    }
  }

  validate(
      _validAddress(
          Address(message.envelopeFrom ?? message.fromAsAddress.mailAddress), message.validator,
          isEnvelope: true),
      'ENV_FROM',
      'Envelope mail address is invalid.  ${message.envelopeFrom}');
  var counter = 0;
  for (var a in (message.envelopeTos ?? <String>[])) {
    counter++;
    validate(
        (a.isNotEmpty), 'ENV_TO_EMPTY', 'Envelope to address (pos: $counter) is null or empty');
    validate(_validAddress(a, message.validator, isEnvelope: true), 'ENV_TO',
        'Envelope to address is invalid.  $a');
  }

  validate(_validAddress(message.from, message.validator), 'FROM_ADDRESS',
      'The from address is invalid.  (${message.from})');
  // An empty explicit recipient list uses the header recipients as its envelope.
  final recipientsAreEnvelope = message.envelopeTos?.isNotEmpty != true;
  counter = 0;
  for (var aIn in message.recipients) {
    counter++;
    Address? a;

    a = aIn is String ? Address(aIn) : aIn as Address?;

    validate(a != null && (a.mailAddress).isNotEmpty, 'TO_ADDRESS_EMPTY',
        'A recipient address is null or empty.  (pos: $counter).');
    if (a != null) {
      validate(_validAddress(a, message.validator, isEnvelope: recipientsAreEnvelope), 'TO_ADDRESS',
          'A recipient address is invalid.  ($a).');
    }
  }
  for (final aIn in [...message.ccRecipients, ...message.bccRecipients]) {
    final address = aIn is String ? Address(aIn) : aIn as Address?;
    validate(
        address != null &&
            _validAddress(address, message.validator, isEnvelope: recipientsAreEnvelope),
        'RECIPIENT_ADDRESS',
        'A CC or BCC address is invalid.');
  }
  try {
    var irMessage = MimeMessage(message);
    if (irMessage.envelopeTos.isEmpty) {
      res.add(Problem('NO_RECIPIENTS', 'Mail does not have any recipients.'));
    }
  } on InvalidHeaderException catch (e) {
    res.add(Problem('INVALID_HEADER', e.message));
  } catch (e) {
    res.add(Problem('INVALID_MESSAGE', 'Could not build internal representation.'));
  }
  return res;
}
