import 'dart:convert';
import 'dart:io';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_range/angel_range.dart';
import 'package:angel_test/angel_test.dart';
import 'package:mock_request/mock_request.dart';
import 'package:test/test.dart';

const String HELLO_WORLD = 'Hello, world!';

main() {
  TestClient client;

  setUp(() async {
    var app = new Angel();

    app.get('/hello', (req, res) async {
      res
        ..write(HELLO_WORLD)
        ..end();
    });

    app.fatalErrorStream.listen((AngelFatalError e) async {
      // Hack until https://github.com/angel-dart/framework/issues/144 is resolved
      print('Fatal: ${e.error}');
      if (e.error is AngelHttpException) {
        var err = e.error as AngelHttpException;
        var rs = e.request.response;
        print('Sending status: ${err.statusCode}');
        rs.statusCode = err.statusCode;
        rs.headers.contentType = ContentType.JSON;
        rs.write(JSON.encode(err.toJson()));
        return await rs.close();
      }

      e.request.response.close();
    });

    app.responseFinalizers.add(acceptRanges());
    await app.configure(logRequests());
    client = await connectTo(app);
  });

  tearDown(() => client.close());

  group('single range', () {
    test('sets proper status code', () async {
      var response =
          await client.get('/hello', headers: {HttpHeaders.RANGE: 'bytes 3-5'});
      expect(response, hasStatus(HttpStatus.PARTIAL_CONTENT));
    });

    test('sets proper content-range', () async {
      var response =
          await client.get('/hello', headers: {HttpHeaders.RANGE: 'bytes 3-5'});
      expect(response,
          hasHeader(HttpHeaders.CONTENT_RANGE, '3-5/${HELLO_WORLD.length}'));
    });

    test('sends slice of buffer', () async {
      var response =
          await client.get('/hello', headers: {HttpHeaders.RANGE: 'bytes 3-5'});
      print('Response: ${response.body}');
      expect(response, hasBody(HELLO_WORLD.substring(3, 6)));
    });
  });

  group('multiple ranges', () {
    test('sends multipart/byteranges content-type', () async {
      var response = await client
          .get('/hello', headers: {HttpHeaders.RANGE: 'bytes 3-5, 7-8, 9-'});
      expect(response, hasHeader(HttpHeaders.CONTENT_TYPE));
      var headerValue = response.headers[HttpHeaders.CONTENT_TYPE];
      expect(headerValue, matches(r'multipart/byteranges; boundary=([^\n]+)'));
    });

    test('does not set content-range', () async {
      var response = await client
          .get('/hello', headers: {HttpHeaders.RANGE: 'bytes 3-5, 7-8, 9-'});
      expect(response, isNot(hasHeader(HttpHeaders.CONTENT_RANGE)));
    });

    test('sends proper body', () async {
      var rq = new MockHttpRequest('GET', new Uri(path: '/hello'));
      var rs = rq.response;
      rq.headers.set(HttpHeaders.RANGE, 'bytes 3-5, 7-8, 9-');
      await client.server.handleRequest(rq);
      var stream = rs.transform(UTF8.decoder);
      var completeBody = await stream.join();
      print('Body:\n$completeBody');

      var contentType = ContentType.parse(rs.headers.value(HttpHeaders.CONTENT_TYPE));
      var boundary = contentType.parameters['boundary'];
      print('Boundary: $boundary');

      var lines = const LineSplitter().convert(completeBody);
      print(lines);
      expect(lines, hasLength(16));

      expect(lines[0], '--$boundary');
      expect(lines[1], 'Content-Type: text/plain');
      expect(lines[2], 'Content-Range: 3-5/${HELLO_WORLD.length}');
      expect(lines[3], isEmpty);
      expect(lines[4], HELLO_WORLD.substring(3, 6));

      expect(lines[5], '--$boundary');
      expect(lines[6], 'Content-Type: text/plain');
      expect(lines[7], 'Content-Range: 7-8/${HELLO_WORLD.length}');
      expect(lines[8], isEmpty);
      expect(lines[9], HELLO_WORLD.substring(7, 9));

      expect(lines[10], '--$boundary');
      expect(lines[11], 'Content-Type: text/plain');
      expect(lines[12], 'Content-Range: 9-/${HELLO_WORLD.length}');
      expect(lines[13], isEmpty);
      expect(lines[14], HELLO_WORLD.substring(9));

      expect(lines[15], '--$boundary--');
    });
  });

  group('exceptions', () {
    test('empty range', () async {
      var response =
          await client.get('/hello', headers: {HttpHeaders.RANGE: 'bytes'});
      expect(
          response, isAngelHttpException(statusCode: HttpStatus.BAD_REQUEST));
    });

    test('out of range', () async {
      var response = await client.get('/hello',
          headers: {HttpHeaders.RANGE: 'bytes -${HELLO_WORLD.length}'});
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
      expect(
          response,
          isAngelHttpException(
              statusCode: HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE));
    });

    test('semantically invalid range', () async {
      var response = await client
          .get('/hello', headers: {HttpHeaders.RANGE: 'bytes 52-3'});
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
      expect(
          response,
          isAngelHttpException(
              statusCode: HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE));
    });

    test('unsupported range type', () async {
      var response = await client
          .get('/hello', headers: {HttpHeaders.RANGE: 'one 2-3'});
      expect(
          response,
          isAngelHttpException(
              statusCode: HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE));
    });
  });

  test('sends accept-ranges if no `range` sent', () async {
    var response = await client.get('/hello');
    expect(response, hasHeader(HttpHeaders.ACCEPT_RANGES, 'bytes'));
  });
}
