import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:kover/riverpod/providers/tts/tts_engine.dart';

// The protocol of Microsoft Edge's online "Read aloud" voices, ported from the
// edge-tts project. Everything here is pure Dart and has no side effects, so
// it can be tested without network access.

const trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _baseUrl =
    'speech.platform.bing.com/consumer/speech/synthesize/readaloud';
const _chromiumVersion = '143.0.3650.75';
const _chromiumMajor = '143';
const secMsGecVersion = '2-$_chromiumVersion';

/// Used when no voice is selected and none matches the language of the text.
const defaultEdgeVoice = 'en-US-EmmaMultilingualNeural';

const edgeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/$_chromiumMajor.0.0.0 Safari/537.36 '
    'Edg/$_chromiumMajor.0.0.0';

final _random = Random.secure();

/// 16 random bytes as 32 uppercase hex characters.
String randomHex() => [
  for (var i = 0; i < 16; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join().toUpperCase();

/// The `Sec-MS-GEC` token valid for the 5 minute window containing [now].
String secMsGec(DateTime now) {
  const windowsEpoch = 11644473600;
  final seconds = now.millisecondsSinceEpoch ~/ 1000 + windowsEpoch;
  final ticks = (seconds - seconds % 300) * 10000000;
  final data = ascii.encode('$ticks$trustedClientToken');

  final digest = _sha256Digest(data);
  final (first, second) = _cs64Digest(data, digest);
  final cs64 = (ByteData(8)
    ..setUint32(0, first, .little)
    ..setUint32(4, second, .little));
  return '${_hex(cs64.buffer.asUint8List())}-${_hex(digest)}';
}

String _hex(Uint8List bytes) => [
  for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
].join().toUpperCase();

String socketUrl(DateTime now) =>
    'wss://$_baseUrl/edge/v1?TrustedClientToken=$trustedClientToken'
    '&ConnectionId=${randomHex()}'
    '&Sec-MS-GEC=${secMsGec(now)}'
    '&Sec-MS-GEC-Version=$secMsGecVersion';

/// The headers of the WebSocket handshake, except the user agent which is set
/// on the HTTP client.
Map<String, String> socketHeaders() => {
  'Pragma': 'no-cache',
  'Cache-Control': 'no-cache',
  'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
  'Accept-Language': 'en-US,en;q=0.9',
  'Cookie': 'muid=${randomHex()};',
};

String voicesUrl(DateTime now) =>
    'https://$_baseUrl/voices/list?trustedclienttoken=$trustedClientToken'
    '&Sec-MS-GEC=${secMsGec(now)}'
    '&Sec-MS-GEC-Version=$secMsGecVersion';

Map<String, String> voicesHeaders() => {
  'Authority': 'speech.platform.bing.com',
  'Sec-CH-UA':
      '" Not;A Brand";v="99", "Microsoft Edge";v="$_chromiumMajor", '
      '"Chromium";v="$_chromiumMajor"',
  'Sec-CH-UA-Mobile': '?0',
  'Accept': '*/*',
  'Sec-Fetch-Site': 'none',
  'Sec-Fetch-Mode': 'cors',
  'Sec-Fetch-Dest': 'empty',
  'User-Agent': edgeUserAgent,
  'Accept-Language': 'en-US,en;q=0.9',
  'Cookie': 'muid=${randomHex()};',
};

/// Parses the voice list response.
List<TtsVoice> parseVoices(String json) => [
  for (final voice in jsonDecode(json) as List<dynamic>)
    if (voice case {
      'ShortName': final String name,
      'Locale': final String locale,
    })
      TtsVoice(name: name, locale: locale),
];

final _shortName = RegExp(r'^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$');

/// The voice name in the form Microsoft Edge sends, such as
/// `Microsoft Server Speech Text to Speech Voice (en-US, EmmaNeural)`.
String voiceLongName(String shortName) {
  final match = _shortName.firstMatch(shortName);
  if (match == null) return shortName;

  var region = match.group(2)!;
  var name = match.group(3)!;
  final dash = name.indexOf('-');
  if (dash != -1) {
    region = '$region-${name.substring(0, dash)}';
    name = name.substring(dash + 1);
  }
  return 'Microsoft Server Speech Text to Speech Voice '
      '(${match.group(1)}-$region, $name)';
}

String _signed(int value) => '${value >= 0 ? '+' : ''}$value';

/// A speed multiplier as a percentage change, such as `+25%`.
String prosodyRate(double rate) => '${_signed(((rate - 1) * 100).round())}%';

/// A pitch multiplier as a change in Hz, such as `-50Hz`.
String prosodyPitch(double pitch) =>
    '${_signed(((pitch - 1) * 100).round())}Hz';

final _controlCharacters = RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]');

String ssml(String voice, String text, double rate, double pitch) {
  final escaped = text
      .replaceAll(_controlCharacters, ' ')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
      "xml:lang='en-US'><voice name='${voiceLongName(voice)}'>"
      "<prosody pitch='${prosodyPitch(pitch)}' rate='${prosodyRate(rate)}' "
      "volume='+0%'>$escaped</prosody></voice></speak>";
}

/// The date in the JavaScript format the service expects.
String jsDate(DateTime utc) => DateFormat(
  "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'",
  'en_US',
).format(utc);

String configMessage(String date) =>
    'X-Timestamp:$date\r\n'
    'Content-Type:application/json; charset=utf-8\r\n'
    'Path:speech.config\r\n\r\n'
    '{"context":{"synthesis":{"audio":{"metadataoptions":{'
    '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
    '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n';

String ssmlMessage(String requestId, String date, String ssml) =>
    'X-RequestId:$requestId\r\n'
    'Content-Type:application/ssml+xml\r\n'
    // The service expects the extra Z.
    'X-Timestamp:${date}Z\r\n'
    'Path:ssml\r\n\r\n'
    '$ssml';

/// The `Path` header of a text frame.
String? textPath(String frame) {
  final end = frame.indexOf('\r\n\r\n');
  return _headers(end == -1 ? frame : frame.substring(0, end))['Path'];
}

Map<String, String> _headers(String block) => {
  for (final line in block.split('\r\n'))
    if (line.indexOf(':') case final colon when colon > 0)
      line.substring(0, colon): line.substring(colon + 1),
};

/// The audio of a binary frame, or null when the frame carries none.
///
/// Throws a [FormatException] when the frame is not a well formed audio frame.
Uint8List? audioData(Uint8List frame) {
  if (frame.length < 2) {
    throw const FormatException('binary frame is missing the header length');
  }
  final length = frame[0] << 8 | frame[1];
  if (2 + length > frame.length) {
    throw const FormatException('header length exceeds the frame');
  }

  final headers = _headers(utf8.decode(frame.sublist(2, 2 + length)));
  if (headers['Path'] != 'audio') {
    throw const FormatException('binary frame is not audio');
  }
  final body = frame.sublist(2 + length);

  switch (headers['Content-Type']) {
    case null when body.isEmpty:
      return null;
    case null:
      throw const FormatException('audio frame has no content type');
    case 'audio/mpeg' when body.isNotEmpty:
      return body;
    case 'audio/mpeg':
      throw const FormatException('audio frame has no data');
    case final other:
      throw FormatException('unexpected content type $other');
  }
}

// Sec-MS-GEC v2 digest, ported from edge-tts. It is SHA-256 with a state and
// message schedule precomputed from a fixed salt, so it cannot be computed
// with a standard implementation.

const _mask = 0xFFFFFFFF;

const _sha256Initial = [
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, //
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];
const _sha256State = [
  0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, //
  0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
];
const _sha256Schedule = [
  0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, //
  0xC0DD25A0, 0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
  0xD258B060, 0x72766564,
];
const _sha256Round = [
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, //
  0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
  0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786,
  0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147,
  0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
  0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B,
  0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A,
  0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
  0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
];
const _sha256Adjustment = 0xC9DC06A7;
const _sha256Sigma0Adjustment = 0x059C0B80;
const _sha256Sigma1Adjustment = 0x000B92C0;

const _cs64Coefficients = [
  (0xE82E91B1, 0xB32700D0),
  (0x44DE24C6, 0x88DFF51D),
  (0x3BEB65BC, 0x29514038),
  (0xC89C5933, 0xB328CBDF),
  (0x8D1EC211, 0xD405B4D5),
  (0x314EF5D5, 0x26E55F3C),
  (0xE92491B1, 0x607801C6),
  (0xF0A5B9D5, 0x82B2C1FB),
  (0x06064CF3, 0xFA51A3DA),
  (0xDA79FA60, 0x207CC464),
  (0xBED20560, 0x3C3C74F3),
  (0x89F9C9F8, 0xD2D14B61),
  (0x35FA38C6, 0xBB04A2C1),
  (0xCB49E3C6, 0xC5626167),
];
const _cs64Factor = 0x82893933;
const _cs64Adjustment0 = 0xF2F90B1A;
const _cs64Adjustment1 = 0x0B1A0000;

int _rotr(int value, int bits) =>
    ((value >>> bits) | (value << (32 - bits))) & _mask;

int _rol16(int value) => ((value << 16) | (value >>> 16)) & _mask;

int _sigma0(int x) =>
    ((x >>> 7) ^ (x << 25) ^ (x >>> 18) ^ (x << 14) ^ (x >>> 3)) & _mask;

int _sigma1(int x) =>
    ((x >>> 17) ^ (x << 15) ^ (x >>> 19) ^ (x << 13) ^ (x >>> 10)) & _mask;

void _expandSchedule(List<int> words, int first) {
  for (var i = first; i < 64; i++) {
    words.add(
      (_sigma1(words[i - 2]) +
              words[i - 7] +
              _sigma0(words[i - 15]) +
              words[i - 16]) &
          _mask,
    );
  }
}

List<int> _rounds(List<int> state, List<int> words, int first) {
  final constants = first == 14
      ? [..._sha256Round.take(14), _sha256Adjustment, ..._sha256Round.skip(15)]
      : _sha256Round;
  var [a, b, c, d, e, f, g, h] = state;
  for (var i = first; i < 64; i++) {
    final t1 =
        h +
        (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)) +
        (g ^ (e & (f ^ g))) +
        constants[i] +
        words[i];
    final t2 =
        (_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)) + ((a & b) | (c & (a | b)));
    h = g;
    g = f;
    f = e;
    e = (d + t1) & _mask;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & _mask;
  }
  return [a, b, c, d, e, f, g, h];
}

int _big(List<int> bytes) => bytes.fold(0, (acc, byte) => acc << 8 | byte);

/// The state after the first 7 bytes of the data, which are all fixed.
List<int> _sha256Init(Uint8List data) {
  final words = [
    ...List.filled(14, 0),
    _big(data.sublist(0, 3)),
    _big(data.sublist(3, 7)),
  ];
  for (var i = 16; i < 30; i++) {
    var value = _sha256Schedule[i - 16];
    if (i - 2 >= 14) {
      value += i == 16
          ? _sigma1(words[i - 2]) ^ _sha256Sigma1Adjustment
          : _sigma1(words[i - 2]);
    }
    if (i - 7 >= 14) value += words[i - 7];
    if (i - 15 >= 14) {
      value += i == 29
          ? _sigma0(words[i - 15]) ^ _sha256Sigma0Adjustment
          : _sigma0(words[i - 15]);
    }
    words.add(value & _mask);
  }
  words.add(
    (_sigma1(words[28]) +
            words[23] +
            _sigma0(words[15]) +
            words[14] +
            _sha256Adjustment -
            _sha256Round[14]) &
        _mask,
  );
  _expandSchedule(words, 31);

  final working = _rounds(_sha256State, words, 14);
  return [for (var i = 0; i < 8; i++) (_sha256Initial[i] + working[i]) & _mask];
}

Uint8List _sha256Digest(Uint8List data) {
  final length = 57 + data.length;
  final padded = BytesBuilder()
    ..add(data.sublist(7))
    ..addByte(0x80)
    ..add(Uint8List((55 - length) % 64));
  padded.add(
    (ByteData(8)..setUint64(0, length * 8)).buffer.asUint8List(),
  );

  final bytes = padded.toBytes();
  var state = _sha256Init(data);
  for (var offset = 0; offset < bytes.length; offset += 64) {
    final block = ByteData.sublistView(bytes, offset, offset + 64);
    final words = [for (var i = 0; i < 16; i++) block.getUint32(i * 4)];
    _expandSchedule(words, 16);
    final working = _rounds(state, words, 0);
    state = [for (var i = 0; i < 8; i++) (state[i] + working[i]) & _mask];
  }

  final digest = ByteData(32);
  for (var i = 0; i < 8; i++) {
    digest.setUint32(i * 4, state[i]);
  }
  return digest.buffer.asUint8List();
}

(int, int) _cs64Digest(Uint8List data, Uint8List digest) {
  final key = ByteData.sublistView(digest);
  final keyA = key.getUint32(0, .little) | 1;
  final keyB = key.getUint32(4, .little) | 1;
  final factors = [(keyA * _cs64Factor) & _mask, (keyB * _cs64Factor) & _mask];

  final terms = <int>[];
  final offsets = <int>[];
  for (final (index, (coefficient, offset)) in _cs64Coefficients.indexed) {
    terms.add((coefficient * factors[index % 2]) & _mask);
    offsets.add(offset);
  }

  final prefixed = Uint8List(data.length + 1)
    ..setRange(1, data.length + 1, data);
  var wordCount = (prefixed.length + 3) ~/ 4;
  if (wordCount.isOdd) wordCount++;
  final padded = Uint8List(wordCount * 4)
    ..setRange(0, prefixed.length, prefixed);
  final view = ByteData.sublistView(padded);
  for (var index = 0; index < wordCount; index++) {
    final word = view.getUint32(index * 4, .little);
    var term = word * (index.isEven ? keyA : keyB);
    var offset = _rol16(word) * (index.isEven ? 0xEF0569FB : 0xC31713DB);
    if (index == 0) {
      term += _cs64Adjustment0 * factors[0];
      offset += _cs64Adjustment1;
    }
    terms.add(term & _mask);
    offsets.add(offset & _mask);
  }

  var swapAcc = 0;
  var swapLast = 0;
  var state = 0;
  var acc = 0;
  for (var index = 0; index < terms.length; index += 2) {
    final x = terms[index];
    final y = terms[index + 1];

    var t = _rol16((offsets[index] + x) & _mask);
    var q = (t * 0x76F50F34) & _mask;
    swapAcc += (_rol16(q) * 0xC3EFEA97 + q) & _mask;
    t = _rol16((offsets[index + 1] + y) & _mask);
    q = (t * 0x1881CE3C) & _mask;
    swapLast = (_rol16(q) * 0x35BD1EC9 + q) & _mask;
    swapAcc = (swapAcc + swapLast) & _mask;

    state = (state * keyA + x) & _mask;
    state = (_rol16(state) * 0xCF98B111) & _mask;
    state = (_rol16(state) * 0x87085B9F) & _mask;
    state = (_rol16(state) * 0x12CEB96D) & _mask;
    state = (_rol16(state) * 0x257E1D83) & _mask;
    acc += state;
    t = (state * keyB + y) & _mask;
    t = (_rol16(t) * 0xA27416F5) & _mask;
    t = (_rol16(t) * 0xD38396FF) & _mask;
    state = (_rol16((_rol16(t) * 0x7C932B89) & _mask) * 0xBFA49F69) & _mask;
    acc = (acc + state) & _mask;
  }
  return (swapLast ^ state, swapAcc ^ acc);
}
