import 'dart:convert';

import 'package:mailer/src/core/address.dart';
import 'package:mailer/src/core/attachment.dart';
import 'package:mailer/src/core/address_validator.dart';
import 'package:mailer/src/core/message.dart';
import 'package:mailer/src/smtp/validator.dart';
import 'package:test/test.dart';

void main() {
  group('PracticalAddressValidator', () {
    const validator = PracticalAddressValidator();

    group('accepts valid addresses', () {
      test('simple address', () {
        expect(validator.validate(Address('test@example.com')), isTrue);
      });

      test('with subdomain', () {
        expect(validator.validate(Address('test@mail.example.com')), isTrue);
      });

      test('with plus tag', () {
        expect(validator.validate(Address('user+tag@example.com')), isTrue);
      });

      test('with dots in local-part', () {
        expect(validator.validate(Address('first.last@example.com')), isTrue);
      });

      test('with underscore', () {
        expect(validator.validate(Address('user_name@example.com')), isTrue);
      });

      test('with hyphen', () {
        expect(validator.validate(Address('user-name@example.com')), isTrue);
      });

      test('deep subdomain', () {
        expect(validator.validate(Address('user@a.b.c.example.com')), isTrue);
      });

      test('all atext specials', () {
        // These are all valid in the local-part per RFC 5322
        expect(validator.validate(Address('user!def@example.com')), isTrue);
        expect(validator.validate(Address('user#def@example.com')), isTrue);
        expect(validator.validate(Address(r'user$def@example.com')), isTrue);
        expect(validator.validate(Address('user%def@example.com')), isTrue);
        expect(validator.validate(Address('user&def@example.com')), isTrue);
        expect(validator.validate(Address("user'def@example.com")), isTrue);
        expect(validator.validate(Address('user*def@example.com')), isTrue);
        expect(validator.validate(Address('user+def@example.com')), isTrue);
        expect(validator.validate(Address('user-def@example.com')), isTrue);
        expect(validator.validate(Address('user/def@example.com')), isTrue);
        expect(validator.validate(Address('user=def@example.com')), isTrue);
        expect(validator.validate(Address('user?def@example.com')), isTrue);
        expect(validator.validate(Address('user^def@example.com')), isTrue);
        expect(validator.validate(Address('user_def@example.com')), isTrue);
        expect(validator.validate(Address('user`def@example.com')), isTrue);
        expect(validator.validate(Address('user{def@example.com')), isTrue);
        expect(validator.validate(Address('user|def@example.com')), isTrue);
        expect(validator.validate(Address('user}def@example.com')), isTrue);
        expect(validator.validate(Address('user~def@example.com')), isTrue);
      });
    });

    group('rejects domain literals (IP addresses)', () {
      test('IPv4 literal', () {
        expect(validator.validate(Address('user@[192.168.1.1]')), isFalse);
      });

      test('IPv6 literal', () {
        expect(validator.validate(Address('user@[IPv6:2001:db8::1]')), isFalse);
      });

      test('localhost IP', () {
        expect(validator.validate(Address('user@[127.0.0.1]')), isFalse);
      });
    });

    group('rejects quoted strings', () {
      test('quoted local-part', () {
        expect(validator.validate(Address('"john doe"@example.com')), isFalse);
      });

      test('quoted with special chars', () {
        expect(validator.validate(Address('"john@doe"@example.com')), isFalse);
      });

      test('empty quoted string', () {
        expect(validator.validate(Address('""@example.com')), isFalse);
      });
    });

    group('rejects domains without dot', () {
      test('localhost', () {
        expect(validator.validate(Address('user@localhost')), isFalse);
      });

      test('single label domain', () {
        expect(validator.validate(Address('user@intranet')), isFalse);
      });
    });

    group('rejects malformed addresses', () {
      test('empty address', () {
        expect(validator.validate(Address('')), isFalse);
      });

      test('no @', () {
        expect(validator.validate(Address('userexample.com')), isFalse);
      });

      test('no domain', () {
        expect(validator.validate(Address('user@')), isFalse);
      });

      test('no local-part', () {
        expect(validator.validate(Address('@example.com')), isFalse);
      });

      test('leading dot in local-part', () {
        expect(validator.validate(Address('.user@example.com')), isFalse);
      });

      test('trailing dot in local-part', () {
        expect(validator.validate(Address('user.@example.com')), isFalse);
      });

      test('consecutive dots in local-part', () {
        expect(validator.validate(Address('user..name@example.com')), isFalse);
      });

      test('leading dot in domain', () {
        expect(validator.validate(Address('user@.example.com')), isFalse);
      });

      test('trailing dot in domain', () {
        expect(validator.validate(Address('user@example.com.')), isFalse);
      });

      test('space in local-part', () {
        expect(validator.validate(Address('user name@example.com')), isFalse);
      });

      test('comment in address', () {
        // Comments start with (
        expect(validator.validate(Address('(comment)user@example.com')), isFalse);
      });
    });
  });

  group('StrictAddressValidator', () {
    const validator = StrictAddressValidator();

    test('accepts valid addresses', () {
      expect(validator.validate(Address('test@example.com')), isTrue);
      expect(validator.validate(Address('first.last@example.com')), isTrue);
      expect(validator.validate(Address('"quoted name"@example.com')), isTrue);
    });

    test('rejects invalid addresses', () {
      expect(validator.validate(Address('plainstring')), isFalse);
      expect(validator.validate(Address('test@')), isFalse);
      expect(validator.validate(Address('@example.com')), isFalse);
      expect(validator.validate(Address('test@example@com')), isFalse);
      expect(validator.validate(Address('test space@example.com')), isFalse);
    });
  });

  group('RFC 5322 Edge Cases', () {
    const validator = StrictAddressValidator();

    group('Valid unusual addresses', () {
      test('quoted local-part with specials', () {
        // RFC 5322 §3.2.4: quoted-string allows special characters
        expect(validator.validate(Address('"john.doe"@example.com')), isTrue);
        expect(validator.validate(Address('"john@doe"@example.com')), isTrue);
        expect(validator.validate(Address('"john doe"@example.com')), isTrue);
      });

      test('quoted local-part with escaped characters', () {
        // Quoted-pair: backslash-escaped characters
        expect(validator.validate(Address(r'"john\"doe"@example.com')), isTrue);
        expect(validator.validate(Address(r'"john\\doe"@example.com')), isTrue);
      });

      test('all atext special characters', () {
        // RFC 5322 §3.2.3: atext includes !#$%&'*+-/=?^_`{|}~
        expect(validator.validate(Address('user!def@example.com')), isTrue);
        expect(validator.validate(Address('user#def@example.com')), isTrue);
        expect(validator.validate(Address(r'user$def@example.com')), isTrue);
        expect(validator.validate(Address('user%def@example.com')), isTrue);
        expect(validator.validate(Address('user&def@example.com')), isTrue);
        expect(validator.validate(Address("user'def@example.com")), isTrue);
        expect(validator.validate(Address('user*def@example.com')), isTrue);
        expect(validator.validate(Address('user+def@example.com')), isTrue);
        expect(validator.validate(Address('user-def@example.com')), isTrue);
        expect(validator.validate(Address('user/def@example.com')), isTrue);
        expect(validator.validate(Address('user=def@example.com')), isTrue);
        expect(validator.validate(Address('user?def@example.com')), isTrue);
        expect(validator.validate(Address('user^def@example.com')), isTrue);
        expect(validator.validate(Address('user_def@example.com')), isTrue);
        expect(validator.validate(Address('user`def@example.com')), isTrue);
        expect(validator.validate(Address('user{def@example.com')), isTrue);
        expect(validator.validate(Address('user|def@example.com')), isTrue);
        expect(validator.validate(Address('user}def@example.com')), isTrue);
        expect(validator.validate(Address('user~def@example.com')), isTrue);
      });

      test('combined atext specials', () {
        expect(validator.validate(Address("!#\$%&'*+-/=?^_`{|}~@example.com")), isTrue);
      });

      test('domain literal (IPv4)', () {
        // RFC 5322 §3.4.1: domain-literal allows IP addresses
        expect(validator.validate(Address('user@[192.168.1.1]')), isTrue);
        expect(validator.validate(Address('user@[127.0.0.1]')), isTrue);
      });

      test('domain literal (IPv6)', () {
        expect(validator.validate(Address('user@[IPv6:2001:db8::1]')), isTrue);
        expect(validator.validate(Address('user@[IPv6:2001:db8:85a3::8a2e:370:7334]')), isTrue);
      });

      test('deep subdomain', () {
        expect(validator.validate(Address('user@sub.sub.sub.example.com')), isTrue);
      });

      test('minimal valid address', () {
        expect(validator.validate(Address('a@b.c')), isTrue);
      });

      test('numeric local-part', () {
        expect(validator.validate(Address('123@example.com')), isTrue);
        expect(validator.validate(Address('1@2.3')), isTrue);
      });

      test('very long but valid local-part', () {
        // RFC 5321 limits local-part to 64 characters
        final longLocal = 'a' * 64;
        expect(validator.validate(Address('$longLocal@example.com')), isTrue);
      });

      test('comments', () {
        // Comments are allowed in strict mode
        expect(validator.validate(Address('(comment)user@example.com')), isTrue);
        expect(validator.validate(Address('user(comment)@example.com')), isTrue);
        expect(validator.validate(Address('user@(comment)example.com')), isTrue);
        expect(validator.validate(Address('user@example.com(comment)')), isTrue);
        expect(validator.validate(Address('user.(comment)name@example.com')), isTrue);
        expect(validator.validate(Address('user(nested(comment))@example.com')), isTrue);
      });
    });

    group('Invalid addresses', () {
      test('unquoted space in local-part', () {
        expect(validator.validate(Address('test user@example.com')), isFalse);
      });

      test('missing domain', () {
        expect(validator.validate(Address('test@')), isFalse);
      });

      test('missing local-part', () {
        expect(validator.validate(Address('@example.com')), isFalse);
      });

      test('multiple unquoted @', () {
        expect(validator.validate(Address('test@example@com')), isFalse);
      });

      test('empty string', () {
        expect(validator.validate(Address('')), isFalse);
      });

      test('only @', () {
        expect(validator.validate(Address('@')), isFalse);
      });

      test('unquoted special characters', () {
        // These specials require quoting
        expect(validator.validate(Address('test<>@example.com')), isFalse);
        expect(validator.validate(Address('test,user@example.com')), isFalse);
        expect(validator.validate(Address('test;user@example.com')), isFalse);
        expect(validator.validate(Address('test:user@example.com')), isFalse);
      });

      test('trailing dot in domain', () {
        // While technically valid in DNS, SMTP requires no trailing dot
        expect(validator.validate(Address('test@example.com.')), isFalse);
      });

      test('leading dot in local-part', () {
        expect(validator.validate(Address('.test@example.com')), isFalse);
      });

      test('consecutive dots in local-part', () {
        expect(validator.validate(Address('test..user@example.com')), isFalse);
      });

      test('unterminated quoted string', () {
        expect(validator.validate(Address('"unclosed@example.com')), isFalse);
      });

      test('unterminated domain literal', () {
        expect(validator.validate(Address('user@[192.168.1.1')), isFalse);
      });
    });
  });

  group('Message Validation', () {
    test('uses default validator by default', () {
      final message = Message()
        ..from = 'test@example.com'
        ..recipients.add('valid@example.com');

      final problems = validate(message);
      expect(problems, isEmpty);
    });

    test('uses custom validator', () {
      final message = Message()
        ..from = 'test@example.com'
        ..recipients.add('invalid-for-strict');

      message.validator = const StrictAddressValidator();

      final problems = validate(message);
      expect(problems, isNotEmpty);
      expect(problems.any((p) => p.msg.contains('invalid-for-strict')), isTrue);
    });

    test('allows permissive validator', () {
      final message = Message()
        ..from = 'test@example.com'
        ..recipients.add('anything-goes');

      message.validator = const PermissiveAddressValidator();

      final problems = validate(message);
      expect(problems, isEmpty);
    });
  });

  group('Injection', () {
    Message message() => Message()
      ..from = 'sender@example.com'
      ..recipients.add('recipient@example.com')
      ..text = 'hello';

    List<String> codes(Message message) => validate(message).map((p) => p.code).toList();

    test('rejects SMTP commands in cc and bcc addresses', () {
      const attack = 'victim@example.com>\r\nRCPT TO:<attacker@example.net';
      expect(codes(message()..ccRecipients.add(attack)), contains('CC_ADDRESS'));
      expect(codes(message()..bccRecipients.add(attack)), contains('BCC_ADDRESS'));
    });

    const optionAttack = 'sender@example.com> RET=HDRS ENVID=owned';
    final setters = <String, void Function(Message)>{
      'envelopeFrom': (m) => m.envelopeFrom = optionAttack,
      'envelopeTos': (m) => m.envelopeTos = [optionAttack],
      'from': (m) => m.from = optionAttack,
      'recipients': (m) => m.recipients.add(optionAttack),
      'ccRecipients': (m) => m.ccRecipients.add(optionAttack),
      'bccRecipients': (m) => m.bccRecipients.add(optionAttack),
    };
    for (final entry in setters.entries) {
      for (final validator in [null, const PermissiveAddressValidator()]) {
        test('rejects ESMTP parameters in ${entry.key} (validator: $validator)', () {
          final m = message()..validator = validator;
          entry.value(m);
          expect(validate(m), isNotEmpty);
        });
      }
    }

    test('ignores bcc addresses if envelopeTos is set', () {
      final m = message()
        ..validator = const StrictAddressValidator()
        ..envelopeTos = ['recipient@example.com']
        ..bccRecipients.add('invalid-bcc');
      expect(validate(m), isEmpty);
    });

    test('allows null reverse-path if the validator accepts it', () {
      final m = message()
        ..validator = const _AcceptAllValidator()
        ..envelopeFrom = '';
      expect(validate(m), isEmpty);
      m.envelopeTos = [''];
      expect(codes(m), contains('ENV_TO_EMPTY'));
    });

    test('rejects folded SMTP commands accepted by StrictAddressValidator', () {
      const address = 'victim(comment\r\nNOOP\r\n)@example.com';
      final m = message()
        ..validator = const StrictAddressValidator()
        ..from = const Address(address);
      expect(codes(m), containsAll(['ENV_FROM', 'INVALID_HEADER']));
      m.envelopeFrom = 'sender@example.com';
      expect(codes(m), contains('INVALID_HEADER'));
    });

    for (final address in [
      'bob@example.com (Support)',
      'bob@example.com\t(Support)',
      'bob@example.com\r\n (Support)',
    ]) {
      final name = jsonEncode(address);
      test('allows CFWS in header addresses with explicit envelope: $name', () {
        final m = Message()
          ..validator = const StrictAddressValidator()
          ..from = Address(address)
          ..recipients.add(Address(address))
          ..ccRecipients.add(Address(address))
          ..envelopeFrom = 'sender@example.com'
          ..envelopeTos = ['recipient@example.com'];
        expect(validate(m), isEmpty);
      });

      test('rejects CFWS in envelope addresses: $name', () {
        final m = Message()
          ..validator = const StrictAddressValidator()
          ..from = Address(address)
          ..recipients.add(Address(address))
          ..ccRecipients.add(Address(address))
          ..bccRecipients.add(Address(address));
        expect(codes(m), containsAll(['ENV_FROM', 'TO_ADDRESS', 'CC_ADDRESS', 'BCC_ADDRESS']));

        final explicit = message()
          ..validator = const StrictAddressValidator()
          ..envelopeFrom = address
          ..envelopeTos = [address];
        expect(codes(explicit), containsAll(['ENV_FROM', 'ENV_TO']));
      });
    }

    for (final address in [
      'a@example.com\r\nx-injected: yes',
      'a@example.com\nx-injected: yes',
      'a@example.com\r x-injected: yes',
    ]) {
      test('rejects control characters in address headers: ${jsonEncode(address)}', () {
        expect(
            codes(message()..headers['reply-to'] = Address(address)), contains('INVALID_HEADER'));
      });
    }

    test('checks the encoded address of address headers', () {
      expect(codes(message()..headers['reply-to'] = const _UnsafeEncodedAddress()),
          contains('INVALID_HEADER'));
    });

    test('rejects invalid header names', () {
      expect(codes(message()..headers['x-original\r\nx-injected'] = 'yes'),
          contains('INVALID_HEADER'));
      final attachment = StringAttachment('x')
        ..additionalHeaders['x-original\r\nx-injected'] = 'yes';
      expect(codes(message()..attachments.add(attachment)), contains('INVALID_HEADER'));
    });
  });

  group('Validator comparison', () {
    const practicalV = PracticalAddressValidator();
    const strictV = StrictAddressValidator();

    test('PracticalAddressValidator is stricter than StrictAddressValidator', () {
      // These pass Strict but fail Default
      final strictOnlyAddresses = [
        '"quoted"@example.com',
        'user@[192.168.1.1]',
        'user@localhost',
      ];

      for (final addr in strictOnlyAddresses) {
        expect(strictV.validate(Address(addr)), isTrue, reason: 'Strict should accept: $addr');
        expect(practicalV.validate(Address(addr)), isFalse, reason: 'Default should reject: $addr');
      }
    });

    test('Both accept standard addresses', () {
      final standardAddresses = [
        'user@example.com',
        'user.name@example.com',
        'user+tag@mail.example.com',
      ];

      for (final addr in standardAddresses) {
        expect(strictV.validate(Address(addr)), isTrue, reason: 'Strict should accept: $addr');
        expect(practicalV.validate(Address(addr)), isTrue, reason: 'Default should accept: $addr');
      }
    });
  });

  group('Validate Error Codes', () {
    test('invalid recipient returns TO_ADDRESS error', () {
      final message = Message()
        ..from = 'sender@example.com'
        ..recipients.add('invalid-recipient');

      // Use a strict validator to ensure 'invalid-recipient' is considered invalid
      message.validator = const StrictAddressValidator();

      final problems = validate(message);
      expect(problems, isNotEmpty);
      expect(problems.map((p) => p.code), contains('TO_ADDRESS'));
      expect(problems.map((p) => p.code), isNot(contains('FROM_ADDRESS')));
    });
  });
}

class _UnsafeEncodedAddress extends Address {
  const _UnsafeEncodedAddress() : super('safe@example.com');

  @override
  String get encodedAddress => 'unsafe@example.com\r\nx-injected: yes';
}

class _AcceptAllValidator implements AddressValidator {
  const _AcceptAllValidator();

  @override
  bool validate(Address address) => true;
}
