import 'package:mailer/src/core/address.dart';
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

    test('accepts comments with legal folding whitespace', () {
      expect(validator.validate(Address('bob@example.com\t(Support)')), isTrue);
      expect(validator.validate(Address('bob@example.com\r\n (Support)')), isTrue);
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
    test('default validator rejects a missing closing quote', () {
      final message = Message()
        ..from = '"@example.com'
        ..recipients.add('recipient@example.com')
        ..envelopeFrom = 'sender@example.com';

      expect(validate(message).map((problem) => problem.code), contains('FROM_ADDRESS'));
    });

    for (final address in [
      'bob@example.com (Support)',
      'bob@example.com\t(Support)',
      'bob@example.com\r\n (Support)',
    ]) {
      test('explicit envelopes allow strict CFWS headers: ${address.codeUnits}', () {
        final message = Message()
          ..validator = const StrictAddressValidator()
          ..from = Address(address)
          ..recipients.add(Address(address))
          ..ccRecipients.add(Address(address))
          ..bccRecipients.add(Address(address))
          ..envelopeFrom = 'sender@example.com'
          ..envelopeTos = ['recipient@example.com'];

        expect(validate(message), isEmpty);
      });

      for (final envelopeTos in <List<String>?>[null, []]) {
        test(
            'strict CFWS fallback paths are rejected (envelopeTos=$envelopeTos): '
            '${address.codeUnits}', () {
          final message = Message()
            ..validator = const StrictAddressValidator()
            ..from = Address(address)
            ..recipients.add(Address(address))
            ..ccRecipients.add(Address(address))
            ..bccRecipients.add(Address(address))
            ..envelopeTos = envelopeTos;

          expect(validate(message).map((problem) => problem.code),
              containsAll(['ENV_FROM', 'TO_ADDRESS', 'RECIPIENT_ADDRESS']));
        });
      }

      test('strict CFWS explicit envelope paths are rejected: ${address.codeUnits}', () {
        final message = Message()
          ..validator = const StrictAddressValidator()
          ..from = 'sender@example.com'
          ..recipients.add('recipient@example.com')
          ..envelopeFrom = address
          ..envelopeTos = [address];

        expect(
            validate(message).map((problem) => problem.code), containsAll(['ENV_FROM', 'ENV_TO']));
      });
    }

    test('explicit envelopes retain configured validation of header addresses', () {
      final message = Message()
        ..validator = const StrictAddressValidator()
        ..from = 'invalid-from'
        ..recipients.add('invalid-to')
        ..ccRecipients.add('invalid-cc')
        ..bccRecipients.add('invalid-bcc')
        ..envelopeFrom = 'sender@example.com'
        ..envelopeTos = ['recipient@example.com'];

      expect(validate(message).map((problem) => problem.code),
          containsAll(['FROM_ADDRESS', 'TO_ADDRESS', 'RECIPIENT_ADDRESS']));
    });

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
