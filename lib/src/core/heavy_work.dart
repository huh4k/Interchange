import 'dart:async';
import 'dart:isolate';

/// Payloads smaller than this are cheaper to process inline than to ship to
/// another isolate.
const int kIsolateThresholdBytes = 128 * 1024;

/// Runs [task] on a background isolate when [payloadSize] is large enough for
/// the work to risk dropping frames on the UI isolate; otherwise runs it inline.
///
/// [task] must only capture sendable values (strings, bytes, plain data).
Future<T> runHeavy<T>(
  int payloadSize,
  FutureOr<T> Function() task, {
  int threshold = kIsolateThresholdBytes,
}) {
  if (payloadSize < threshold) {
    return Future<T>.sync(task);
  }
  return Isolate.run<T>(task);
}
