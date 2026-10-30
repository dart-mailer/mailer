## 7.2.1
* Security: Fix SMTP command and MIME header injection (GHSA-j9fr-mx5c-8w5v).
  - Reject control characters in SMTP commands and `<`, `>`, spaces in unquoted envelope addresses.
  - Validate `ccRecipients` and `bccRecipients` (new problem codes `CC_ADDRESS` and `BCC_ADDRESS`).
  - `PersistentConnection.send` now validates messages and throws `SmtpMessageValidationException`.
  - Reject invalid header names and control characters in address headers.
  - Escape quotes and backslashes in quoted header parameters and display names.
* Security: Limit SMTP server responses (GHSA-8jpq-5wmr-fpqm).
  - Response lines are limited to 8192 characters, responses to 100 lines and 64 KiB.
  - `timeout` now applies to the whole response instead of every line.
* `PersistentConnection` sends messages one after another and reconnects after a failed send.
* Accept server responses consisting only of a response code.
  Thanks https://github.com/bsutton for reporting and providing the initial fix.

## 7.2.0
* Upgrade `punycoder` to v0.3.0.
* Refactor IDNA module to use `domainToAscii` and `domainToUnicode` from `punycoder`.
* Refactor `Address.encodedAddress` to use `emailToAscii` from `punycoder`.
* Maintain `IdnaException` for backward compatibility by wrapping `punycoder`'s `FormatException`.

## 7.1.0
* allow mime 2.0.0 and intl up to 0.21.0
  Thanks https://github.com/karelklic

## 7.0.0
* Major Refactoring: Simplified library structure and standardized exports.
  - Renamed internal `IR` classes to `Mime`.
  - Moved files into `core`, `mime`, and `smtp` directories.
  - Standardized on relative imports within the package.
  - Moved to community repository (github.com/dart-mailer/mailer)
* Feature: Added support for RFC 3030 (CHUNKING and BINARYMIME).
* Feature: Implemented Custom Address Validation API.
  - Added `PracticalAddressValidator` (recommended for input validation).
  - Added `StrictAddressValidator` (RFC 5322 compliance).
  - Added `PermissiveAddressValidator` and `SimpleAddressValidator`.
* Feature: Correct IDNA encoding for domains.
  - Proper NFC Unicode normalization using `unorm_dart`.
  - Case folding and label validation (RFC 5890).
* Breaking: Removed `lib/src/core/entities.dart`. Import `package:mailer/mailer.dart` instead.
* Update: Bumped SDK constraint to Dart 3.

## 6.6.0
* Add Amazon simple Email Service stmp server
  Thanks https://github.com/karelklic

## 6.5.0
* Add brevo stmp server
  Thanks https://github.com/FBanitz

## 6.4.1
* Fix dependency range for intl library.  
  Thanks https://github.com/isoos and https://github.com/mnordine

## 6.4.0
* Switch to `^0.17` instead of range for the intl dependency.  
  Thanks https://github.com/mnordine

## 6.3.0
* Allow mime 2.*

## 6.2.0
* Limit base64 encoded lines to 76 characters.
  Thanks https://github.com/isoos

## 6.1.2
* Fix error code if recipients mail address is empty.  
  Thanks https://github.com/amugofjava

## 6.1.1
* Close connections in finally block  
  Thanks https://github.com/darkstarx

## 6.1.0
* Add auth plain  
  Thanks https://github.com/michep
* Allow `intl 0.19.0` as dependency

## 6.0.1
* Fix yahoo definition  
  Thanks https://github.com/schneiti 

## 6.0.0
* Allow `intl 0.18` as dependency
* Major version upgrade because `mail_sender.dart` no longer exposes `mailSendTasks`.
* Switch from `pedantic` to `lints`

## 5.3.0
* add possibility to add custom header to attachments  
  Thanks https://github.com/dsyrstad

## 5.2.0
* fix non-ascii attachment name  
  Thanks https://github.com/holyens

## 5.1.1
* Specify locale for date headers  
  Thanks https://github.com/michael-spf for the bug report

## 5.1.0
* Include the SMTP error code in the authentication failure exception  
  Thanks: https://github.com/jonasfj
* Add support for parsing a list of rfc5322 mailbox-formatted addresses  
  Thanks: https://github.com/dsyrstad

## 5.0.2
* Fix Null error when closing smtp connection  
  Thanks: https://github.com/hpoul

## 5.0.1
* Fix null-safety migration bug with bad type cast.

## 5.0.0
* minor interface changes.  Some are now const / final objects.
* added a lot of tests
* names of addresses may contain unicode characters now  
  still no punycode support!

## 4.0.0
* null safety and cleanups  
  Thanks: https://github.com/bsutton
  
## 3.3.0
* add sendgrid smtp server  
  Thanks: https://github.com/rohanthacker

## 3.2.1
* Fix compile time bug. 😳

## 3.2.0
* The generation of the mailbox address is done via `Address.toString()`, so application can override it to provide its own sanitization, if necessary.

## 3.1.0
* Improve gmail integration utilities.
* Discourage use of username/password authentication through deprecation.

## 3.0.4
* fix null pointer when server doesn't support EHLO (#121)

## 3.0.3
* fix splitting of text for base64 conversion.

## 3.0.2
* some (dart) file operations changed the return type from `List<int>` to `Uint8List`
  Implemented the proposed fixes from: https://groups.google.com/forum/#!topic/flutter-announce/LTe4SYU8-0Q

## 3.0.1
* allow older pedantic version to make mailer compatible with flutter.

## 3.0.0
* NO BUGFIXES.  There is no *need* to update!
* remove dart 1 compatible code.  mailer does require dart 2.2.2 or higer now.
* remove `catchExceptions` flag.  mailer now always throws.
* change return value of `send` from `List<SendReport>` to `SendReport`
* add persistent connection (idea from https://github.com/jodinathan)
* add xoauth2 authentication method (see examples)

## 2.5.1
* assign `catchExceptions` if null 

## 2.5.0
* export exceptions.

## 2.4.0
* add `catchExceptions` flag to `send` command.  (issue #90)

## 2.3.0
* add timeout option.  (https://github.com/pjkroll)
* add `catchExceptions` flag (currently true, but default will change to false)
  improve exceptions.
* remove username from authentication failure exception (see issue #79)

## 2.2.1
* fix regular expression which is used to validate the name of an email address. 

## 2.2.0
* add qq smtp server definition

## 2.1.2
* improve exception when server response does not match.

## 2.1.1
* if a header value is `null` send empty string instead.
* if mime library fails to identify content use `text/plain` and `application/octet-stream`  
  as defaults.
* mention mailer2 and mailer3 in README

## 2.1.0
* provide smtp_servers in smtp_server.dart

## 2.0.2
* added smtp configuration for mailgun.org

## >1.1.4 \<2.0.2
Please see README and commits.

## 1.1.4
* Remove extra trailing `\r\n` from messages as some servers may interpret it as an empty
 command and send back an error code after success code

## 1.1.3
* Fix occasional issue with completer already completed. Due to an error with SMTP server
closing connection after sending the email.

## 1.1.2
* Fix new lines sent to server to be proper `\r\n` format

## 1.1.1
* loosen crypto dependency to '>=0.9.0 <3.0.0' as suggested in the
    [crypto changelog](https://github.com/dart-lang/crypto/blob/master/CHANGELOG.md#200)

## 1.1.0
* merge crypto util fix and update example
* upgrade unittest to test and move it to dev_dependencies
* added OpenMailBoxSmtpOptions
* improve address parsing and sanitization (from hoylen)
* cleanup chunkEncodedBytes and associated test
* update example to allow CC and BCC

## 1.0.1
* add simple example/send_gmail.data
* fix pubspec to pull crypto 0.9.0

## 1.0.0 - Oct 4, 2015
* initial release
