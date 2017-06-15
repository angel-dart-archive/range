import 'dart:math' as math;
import 'dart:io';
import 'package:angel_framework/angel_framework.dart';
import 'package:range_header/range_header.dart';

final math.Random _rnd = new math.Random();

String _randomString(
    {int length: 32,
    String validChars:
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'}) {
  var len = _rnd.nextInt((length - 10)) + 10;
  var buf = new StringBuffer();

  while (buf.length < len)
    buf.writeCharCode(validChars.codeUnitAt(_rnd.nextInt(validChars.length)));

  return buf.toString();
}

/// A function that parses a string into a [RangeHeader].
typedef RangeHeader RangeHeaderParser(String headerString);

/// Processes a request containing a `Range` header. Otherwise, sends an `Accept-Ranges` header.
///
/// You can provide *additional* range header [parsers]. The default works in almost every case, and allows you to parse
/// `byte` ranges without any further configuration.
///
/// It is recommended to only use this as a response finalizer.
RequestHandler acceptRanges(
    {Map<String, RangeHeaderParser> parsers: const {}}) {
  Map<String, RangeHeaderParser> _parsers = {'bytes': parseRangeHeader}
    ..addAll(parsers ?? {});
  var _acceptedRanges = _parsers.keys.join(',');

  return (RequestContext req, ResponseContext res) async {
    var rangeHeaderString = req.headers.value(HttpHeaders.RANGE);

    if (rangeHeaderString?.isNotEmpty != true) {
      // If neither header is present, then let the client know
      // that we accepted range requests.
      res.headers[HttpHeaders.ACCEPT_RANGES] = _acceptedRanges;
    } else if (rangeHeaderString?.isNotEmpty == true)
      return await _respondToRangeHeader(rangeHeaderString, _parsers, req, res);
    else
      return true;
  };
}

_respondToRangeHeader(
    String rangeHeaderString,
    Map<String, RangeHeaderParser> parsers,
    RequestContext req,
    ResponseContext res) async {
  for (var type in parsers.keys) {
    try {
      if (rangeHeaderString.startsWith(type)) {
        var header = parsers[type](rangeHeaderString);

        if (header.ranges.length == 1) {
          var range = header.ranges[0];
          verifyRange(range);
          var totalLength = res.buffer.length;
          var originalBuf = res.buffer.takeBytes();
          var chunk = originalBuf.getRange(range.start > -1 ? range.start : 0,
              range.end > -1 ? range.end + 1 : originalBuf.length);
          // Set status code
          res.statusCode = HttpStatus.PARTIAL_CONTENT;
          // Set content-range
          res.headers[HttpHeaders.CONTENT_RANGE] =
              header.toContentRange(totalLength);
          res.buffer.add(chunk.toList());
        } else {
          var originalMimeType = res.contentType?.mimeType ?? 'text/plain';
          var originalBuf = res.buffer.takeBytes();
          var totalLen = originalBuf.length;
          var boundary = _randomString();
          res.statusCode = HttpStatus.PARTIAL_CONTENT;
          res.headers[HttpHeaders.CONTENT_TYPE] =
              'multipart/byteranges; boundary=$boundary';

          for (var range in header.ranges) {
            res.write('--$boundary\r\n');
            res.write('Content-Type: $originalMimeType\r\n');
            res.write('Content-Range: $range/$totalLen\r\n\r\n');
            var chunk = originalBuf.getRange(range.start > -1 ? range.start : 0,
                range.end > -1 ? range.end + 1 : originalBuf.length);
            res.buffer.add(chunk.toList());
            res.write('\r\n');
          }

          res.write('--$boundary--\r\n');
        }
        return;
      }
    } on RangeHeaderParseException catch (e) {
      throw new AngelHttpException.badRequest(
          message: 'Invalid "Range" header: ${e.message}');
    } on RangeError catch (e) {
      res.headers[HttpHeaders.CONTENT_RANGE] = 'bytes */${res.buffer.length}';
      throw new AngelHttpException(e,
          statusCode: HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
          message: e.message);
    }
  }

  throw new AngelHttpException(new Exception("Range not satisfiable"),
      statusCode: HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
      message: 'Range type not supported: "$rangeHeaderString"');
}

/// Ensures that a range is semantically valid. If not, an [AngelHttpException] is thrown.
void verifyRange(RangeHeaderItem range) {
  bool invalid = false;

  if (range.start != -1) {
    invalid = range.end != -1 && range.end < range.start;
  } else
    invalid = range.end == -1;

  if (invalid)
    throw new AngelHttpException(new Exception("Semantically invalid range."),
        statusCode: HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
        message: "Invalid range: $range");
}
