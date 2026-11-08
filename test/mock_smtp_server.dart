import 'dart:convert';
import 'dart:io';

class MockSmtpServer {
  late ServerSocket _serverSocket;
  int get port => _serverSocket.port;
  final List<String> serverLog = [];
  final List<int> bdatData = [];
  bool advertiseBinaryMime = true;
  bool advertiseChunking = true;
  bool advertiseSmtpUtf8 = false;

  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _serverSocket.listen(_handleClient);
  }

  Future<void> stop() async {
    await _serverSocket.close();
  }

  void _handleClient(Socket socket) {
    // The client may close the connection without waiting for our response
    // (e.g. after QUIT). Writing to it then fails with a broken pipe, which
    // would otherwise be reported as an unhandled error in the test.
    socket.done.catchError((_) {});
    socket.write('220 Simple Mock Server Service Ready\r\n');

    var buffer = <int>[];
    var bdatBytesExpected = 0;
    var inBdatData = false;

    socket.listen((data) {
      buffer.addAll(data);

      while (true) {
        if (inBdatData) {
          if (buffer.length >= bdatBytesExpected) {
            bdatData.addAll(buffer.sublist(0, bdatBytesExpected));
            buffer.removeRange(0, bdatBytesExpected);
            inBdatData = false;
            bdatBytesExpected = 0;
            socket.write('250 OK\r\n');
          } else {
            break;
          }
        } else {
          var idx = -1;
          for (var i = 0; i < buffer.length; i++) {
            if (buffer[i] == 10) {
              // \n
              idx = i;
              break;
            }
          }

          if (idx != -1) {
            var lineBytes = buffer.sublist(0, idx + 1);
            var line = utf8.decode(lineBytes).trim();
            buffer.removeRange(0, idx + 1);

            serverLog.add(line);

            if (line.startsWith('EHLO')) {
              var caps = '250-localhost\r\n';
              if (advertiseChunking) {
                caps += '250-CHUNKING\r\n';
              }
              if (advertiseBinaryMime) {
                caps += '250-BINARYMIME\r\n';
              }
              if (advertiseSmtpUtf8) {
                caps += '250-SMTPUTF8\r\n';
              }
              caps += '250 AUTH PLAIN\r\n';
              socket.write(caps);
            } else if (line.startsWith('MAIL FROM') || line.startsWith('RCPT TO')) {
              socket.write('250 OK\r\n');
            } else if (line.toUpperCase().startsWith('BDAT')) {
              var parts = line.split(' ');
              if (parts.length > 1) {
                try {
                  bdatBytesExpected = int.parse(parts[1]);
                  // If size is 0, we still need to handle it.
                  if (bdatBytesExpected > 0) {
                    inBdatData = true;
                  } else {
                    socket.write('250 OK\r\n');
                  }
                } catch (_) {}
              }
            } else if (line == 'QUIT') {
              socket.write('221 Bye\r\n');
              socket.close();
              break;
            } else if (line == 'DATA') {
              socket.write('354 End data with <CR><LF>.<CR><LF>\r\n');
            } else if (line == '.') {
              socket.write('250 OK\r\n');
            }
          } else {
            break;
          }
        }
      }
    }, onError: (_) {});
  }
}
