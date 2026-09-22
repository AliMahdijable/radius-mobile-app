import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cisco_api.dart';

void main() {
  for (final scenario in ['username', 'password-only', 'denied']) {
    test('Telnet $scenario negotiates, handles pages and closes socket',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final disconnected = Completer<void>();
      final commands = <String>[];
      Socket? peer;
      final listener = server.listen((socket) {
        peer = socket;
        var phase = scenario == 'password-only' ? 1 : 0;
        var iacRemaining = 0;
        var line = '';
        var awaitingPage = false;
        socket.add(
            [255]); // Split the Telnet WILL ECHO negotiation across packets.
        Timer(const Duration(milliseconds: 15), () {
          socket.add([251, 1]);
          socket.write(scenario == 'password-only'
              ? '\r\nPassword: '
              : '\r\nUsername: ');
        });
        socket.listen((bytes) {
          for (final b in bytes) {
            if (iacRemaining > 0) {
              iacRemaining--;
              continue;
            }
            if (b == 255) {
              iacRemaining = 2;
              continue;
            }
            if (awaitingPage && b == 32) {
              awaitingPage = false;
              socket.write('\b\b\b\b\b\b\b\b        \b\b\b\b\b\b\b\b'
                  '\r\nModel number : WS-C2960-24TT-L\r\nswitch#');
              continue;
            }
            if (b == 10 || b == 13) {
              if (line.isEmpty) continue;
              final input = line;
              line = '';
              if (phase == 0) {
                phase++;
                socket.write('Password: ');
              } else if (phase == 1) {
                phase++;
                if (scenario == 'denied' || input != 'test-password') {
                  socket.write('\r\n% Login invalid\r\nUsername: ');
                } else {
                  socket.write('\r\nswitch#');
                }
              } else {
                commands.add(input);
                if (input == 'show version') {
                  socket.write(
                      'show version\r\nCisco IOS Software, C2960 Software, '
                      'Version 12.2(35)SE5, RELEASE SOFTWARE (fc1)\r\n--More--');
                  awaitingPage = true;
                } else if (input == 'exit' || input == 'quit') {
                  socket.destroy();
                } else {
                  socket.write('$input\r\nswitch#');
                }
              }
            } else if (b >= 32 && b < 127) {
              line += ascii.decode([b]);
            }
          }
        }, onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        }, onError: (Object _) {
          if (!disconnected.isCompleted) disconnected.complete();
        });
      });
      try {
        final model = await CiscoApi.detectModel(
          host: '127.0.0.1',
          port: server.port,
          protocol: 'telnet',
          user: 'test-user',
          pass: 'test-password',
          timeout: const Duration(seconds: 5),
        );
        expect(model, scenario == 'denied' ? null : 'WS-C2960-24TT-L');
        expect(commands.where((c) => c.startsWith('show ')),
            scenario == 'denied' ? isEmpty : ['show version']);
        await disconnected.future.timeout(const Duration(seconds: 2));
      } finally {
        peer?.destroy();
        await listener.cancel();
        await server.close();
      }
    });
  }
}
