import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kover/riverpod/providers/tts/edge_tts_protocol.dart';

Uint8List _frame(String headers, [List<int> body = const []]) {
  final head = utf8.encode(headers);
  return Uint8List.fromList([
    head.length >> 8,
    head.length & 0xFF,
    ...head,
    ...body,
  ]);
}

DateTime _unix(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('secMsGec', () {
    test('matches the reference implementation', () {
      expect(
        secMsGec(_unix(0)),
        '52BC7A17B50DFEC9-'
        '28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6',
      );
      expect(
        secMsGec(_unix(1700000000)),
        '2CD23A2CA0B2595A-'
        'F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2',
      );
    });

    test('is constant within a 5 minute window', () {
      const expected =
          'BB2B3ADE6A8DD1F3-'
          'B07567543B86F99C3539F563D8D3368C59A22CAF50BF1E35F42DA34792F80A76';
      expect(secMsGec(_unix(1764000000)), expected);
      expect(secMsGec(_unix(1764000299)), expected);
    });
  });

  test('voiceLongName', () {
    expect(
      voiceLongName('en-US-EmmaNeural'),
      'Microsoft Server Speech Text to Speech Voice (en-US, EmmaNeural)',
    );
    expect(
      voiceLongName('zh-CN-liaoning-XiaobeiNeural'),
      'Microsoft Server Speech Text to Speech Voice '
      '(zh-CN-liaoning, XiaobeiNeural)',
    );
    expect(voiceLongName('Something Else'), 'Something Else');
  });

  test('prosody', () {
    expect(prosodyRate(1.0), '+0%');
    expect(prosodyRate(0.5), '-50%');
    expect(prosodyRate(1.25), '+25%');
    expect(prosodyRate(2.0), '+100%');
    expect(prosodyPitch(1.0), '+0Hz');
    expect(prosodyPitch(0.5), '-50Hz');
    expect(prosodyPitch(1.5), '+50Hz');
  });

  test('ssml escapes the text', () {
    expect(
      ssml('en-US-EmmaNeural', 'a & b <c>\x0Bd', 1.0, 1.0),
      "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
      "xml:lang='en-US'><voice name='Microsoft Server Speech Text to Speech "
      "Voice (en-US, EmmaNeural)'><prosody pitch='+0Hz' rate='+0%' "
      "volume='+0%'>a &amp; b &lt;c&gt; d</prosody></voice></speak>",
    );
  });

  test('jsDate', () {
    expect(
      jsDate(DateTime.utc(2026, 11, 24, 8, 5, 3)),
      'Tue Nov 24 2026 08:05:03 GMT+0000 (Coordinated Universal Time)',
    );
  });

  test('messages', () {
    expect(
      configMessage('D'),
      'X-Timestamp:D\r\nContent-Type:application/json; charset=utf-8\r\n'
      'Path:speech.config\r\n\r\n'
      '{"context":{"synthesis":{"audio":{"metadataoptions":'
      '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
      '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n',
    );
    expect(
      ssmlMessage('ID', 'D', '<speak/>'),
      'X-RequestId:ID\r\nContent-Type:application/ssml+xml\r\n'
      'X-Timestamp:DZ\r\nPath:ssml\r\n\r\n<speak/>',
    );
  });

  test('textPath', () {
    expect(textPath('X-RequestId:1\r\nPath:turn.end\r\n\r\n{}'), 'turn.end');
    expect(textPath('Path:turn.start\r\n\r\n{}'), 'turn.start');
    expect(textPath('nothing'), isNull);
  });

  group('audioData', () {
    test('returns the audio', () {
      expect(
        audioData(_frame('Path:audio\r\nContent-Type:audio/mpeg', [1, 2, 3])),
        [1, 2, 3],
      );
    });

    test('ignores the empty end frame', () {
      expect(audioData(_frame('Path:audio')), isNull);
    });

    test('rejects malformed frames', () {
      expect(() => audioData(Uint8List(1)), throwsFormatException);
      expect(
        () => audioData(Uint8List.fromList([0, 9, 65])),
        throwsFormatException,
      );
      expect(() => audioData(_frame('Path:other')), throwsFormatException);
      expect(() => audioData(_frame('Path:audio', [1])), throwsFormatException);
      expect(
        () => audioData(_frame('Path:audio\r\nContent-Type:audio/mpeg')),
        throwsFormatException,
      );
      expect(
        () => audioData(_frame('Path:audio\r\nContent-Type:text/plain', [1])),
        throwsFormatException,
      );
    });
  });

  test('parseVoices', () {
    final voices = parseVoices(
      '[{"ShortName":"en-US-EmmaNeural","Locale":"en-US","Gender":"Female"},'
      '{"Name":"broken"}]',
    );
    expect(voices, hasLength(1));
    expect(voices.single.name, 'en-US-EmmaNeural');
    expect(voices.single.locale, 'en-US');
  });
}
