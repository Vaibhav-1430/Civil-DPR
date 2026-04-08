import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class PerformanceTraceService {
  static final Map<String, Stopwatch> _timers = <String, Stopwatch>{};

  static void start(String traceKey) {
    final sw = Stopwatch()..start();
    _timers[traceKey] = sw;
  }

  static Future<void> end(
    String traceKey, {
    Map<String, Object?> extras = const <String, Object?>{},
  }) async {
    final sw = _timers.remove(traceKey);
    if (sw == null) return;
    sw.stop();

    final durationMs = sw.elapsedMilliseconds;
    if (kDebugMode) {
      debugPrint('[PERF] $traceKey: ${durationMs}ms');
    }

    try {
      final params = <String, Object>{
        'trace_key': traceKey,
        'duration_ms': durationMs,
      };

      extras.forEach((key, value) {
        if (value is String || value is int || value is double || value is bool) {
          params[key] = value as Object;
        }
      });

      await FirebaseAnalytics.instance.logEvent(
        name: 'perf_trace',
        parameters: params,
      );
    } catch (_) {
      // Telemetry must never break app flow.
    }
  }
}
