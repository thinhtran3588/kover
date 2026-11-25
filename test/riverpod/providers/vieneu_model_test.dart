import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kover/riverpod/providers/tts/vieneu/vieneu_model.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late List<String?> ranges;
  late Map<String, List<int>> served;
  var failAfter = -1;

  setUp(() async {
    ranges = [];
    failAfter = -1;
    served = {
      'a.bin': List.generate(1000, (i) => i % 251),
      'b.bin': List.generate(500, (i) => (i * 7) % 251),
    };
    directory = await Directory.systemTemp.createTemp('vieneu_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final data = served[request.uri.pathSegments.last];
      if (data == null) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final start = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final body = data.sublist(start);
      if (failAfter >= 0 && start == 0) {
        // Promises the whole file, sends part of it and drops the connection.
        final socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.add(
          ascii.encode(
            'HTTP/1.1 200 OK\r\ncontent-length: ${body.length}\r\n\r\n',
          ),
        );
        socket.add(body.sublist(0, failAfter));
        await socket.flush();
        socket.destroy();
        return;
      }
      request.response.statusCode = range == null ? 200 : 206;
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  List<VieneuFile> files() => [
    for (final name in served.keys)
      VieneuFile(
        name: name,
        url: 'http://127.0.0.1:${server.port}/$name',
        size: served[name]!.length,
      ),
  ];

  test('downloads every file and reports progress up to the total', () async {
    final progress = <(int, int)>[];
    await downloadVieneuFiles(
      directory,
      files: files(),
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(File('${directory.path}/a.bin').readAsBytesSync(), served['a.bin']);
    expect(File('${directory.path}/b.bin').readAsBytesSync(), served['b.bin']);
    expect(progress.last, (1500, 1500));
    expect(vieneuFilesComplete(directory, files()), isTrue);
    expect(directory.listSync().whereType<File>().length, 2);
  });

  test('skips complete files', () async {
    await downloadVieneuFiles(
      directory,
      files: files(),
      onProgress: (_, _) {},
    );
    ranges.clear();
    await downloadVieneuFiles(
      directory,
      files: files(),
      onProgress: (_, _) {},
    );
    expect(ranges, isEmpty);
  });

  test('resumes a partial file with a range request', () async {
    File('${directory.path}/a.bin.part')
      ..createSync()
      ..writeAsBytesSync(served['a.bin']!.sublist(0, 400));
    await downloadVieneuFiles(
      directory,
      files: files(),
      onProgress: (_, _) {},
    );
    expect(ranges.first, 'bytes=400-');
    expect(File('${directory.path}/a.bin').readAsBytesSync(), served['a.bin']);
  });

  test('keeps the partial file when the connection drops', () async {
    failAfter = 300;
    await expectLater(
      downloadVieneuFiles(directory, files: files(), onProgress: (_, _) {}),
      throwsA(anything),
    );
    expect(File('${directory.path}/a.bin').existsSync(), isFalse);
    expect(File('${directory.path}/a.bin.part').lengthSync(), 300);

    failAfter = -1;
    await downloadVieneuFiles(
      directory,
      files: files(),
      onProgress: (_, _) {},
    );
    expect(File('${directory.path}/a.bin').readAsBytesSync(), served['a.bin']);
  });

  test('rejects a file of the wrong size', () async {
    final wrong = [
      VieneuFile(
        name: 'a.bin',
        url: 'http://127.0.0.1:${server.port}/a.bin',
        size: 999,
      ),
    ];
    await expectLater(
      downloadVieneuFiles(directory, files: wrong, onProgress: (_, _) {}),
      throwsA(isA<HttpException>()),
    );
    expect(File('${directory.path}/a.bin').existsSync(), isFalse);
  });

  test('fails on an HTTP error', () async {
    final missing = [
      VieneuFile(
        name: 'x.bin',
        url: 'http://127.0.0.1:${server.port}/x.bin',
        size: 5,
      ),
    ];
    await expectLater(
      downloadVieneuFiles(directory, files: missing, onProgress: (_, _) {}),
      throwsA(isA<HttpException>()),
    );
  });

  test('stops when cancelled', () async {
    await expectLater(
      downloadVieneuFiles(
        directory,
        files: files(),
        onProgress: (_, _) {},
        cancelled: () => true,
      ),
      throwsStateError,
    );
  });
}
