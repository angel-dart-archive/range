# range
[![Pub](https://img.shields.io/pub/v/angel_range.svg)](https://pub.dartlang.org/packages/angel_range)
[![build status](https://travis-ci.org/angel-dart/range.svg)](https://travis-ci.org/angel-dart/range)
![coverage: 100%](https://img.shields.io/badge/coverage-100%25-green.svg)

Support for handling the `Range` headers using the Angel framework.
Aiming for 100% compliance with the [`Range` specification](http://httpwg.org/specs/rfc7233.html).

# Installation
In your `pubspec.yaml`:

```yaml
dependencies:
  angel_framework: ^1.0.0
  angel_range: ^1.0.0
```

# Usage
The `acceptRanges()` function returns an Angel request handler. This is best used as a
response finalizer.

## Compression
If you are using response compression in your application, make sure to add it *after* `Range` support.
Save yourself a headache!

```dart
configureServer(Angel app) async {
  // Apply `Range` headers, if need be
  app.responseFinalizers.add(acceptRanges());
  
  // Support gzip, deflate compression
  app.responseFinalizers.addAll([gzip(), deflate()]);
}
```