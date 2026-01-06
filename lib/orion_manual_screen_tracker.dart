import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'orion_flutter.dart';
import 'orion_network_tracker.dart';
import 'orion_logger.dart';
import 'orion_frame_metrics.dart';

/// Manual screen tracker for non-MaterialApp navigation
///
/// Features:
/// - Accurate TTID/TTFD with frame stability (same as automatic tracker)
/// - Real janky/frozen frame detection
/// - Top 10 jank clusters with ultra-compact beacon
/// - Frozen frames tracked separately
/// - Screen history stack management
/// - Manual TTFD support for async content
///
/// Usage:
/// ```dart
/// // When navigating to a screen
/// OrionManualTracker.startTracking('HomeScreen');
///
/// // When leaving a screen
/// OrionManualTracker.finalizeScreen('HomeScreen');
///
/// // For async content (optional)
/// OrionManualTracker.markFullyDrawn('HomeScreen');
/// ```
class OrionManualTracker {
  static final Map<String, _ManualScreenMetrics> _screenMetrics = {};
  static final List<String> _screenHistoryStack = [];

  // Manual TTFD support
  static final Map<String, bool> _manualTTFDFlags = {};

  /// 🔄 Start tracking a screen manually
  static void startTracking(String screenName) {
    if (!OrionFlutter.isAndroid) return;

    orionPrint("🚀 [Orion] startTracking() called for: $screenName");

    // If already tracking, finalize previous tracking first
    if (_screenMetrics.containsKey(screenName)) {
      orionPrint("⚠️ [Orion] Already tracking screen: $screenName. Finalizing previous...");
      finalizeScreen(screenName);
    }

    // Update screen history stack
    if (_screenHistoryStack.isEmpty || _screenHistoryStack.last != screenName) {
      _screenHistoryStack.add(screenName);
      orionPrint("📚 [Orion] Pushed $screenName to screen history");
    }

    // Set current screen for network tracking
    OrionNetworkTracker.setCurrentScreen(screenName);
    orionPrint("📍 OrionManualTracker: currentScreenName set to $screenName");

    // Start tracking metrics
    final metrics = _ManualScreenMetrics(screenName);
    _screenMetrics[screenName] = metrics;
    metrics.begin();

    orionPrint("✅ [Orion] Started tracking screen: $screenName");
  }

  /// ✅ Finalize tracking and send beacon
  static void finalizeScreen(String screenName) {
    if (!OrionFlutter.isAndroid) return;

    orionPrint("🔥 [Orion] finalizeScreen() called for: $screenName");

    final metrics = _screenMetrics.remove(screenName);

    // Update screen history stack
    if (_screenHistoryStack.isNotEmpty && _screenHistoryStack.last == screenName) {
      _screenHistoryStack.removeLast();
      orionPrint("📚 [Orion] Popped $screenName from screen history");
    }

    // Clean up manual TTFD flag
    _manualTTFDFlags.remove(screenName);

    if (metrics == null) {
      orionPrint("⚠️ [Orion] No tracking data found for: $screenName. Skipping send.");
      return;
    }

    metrics.send();
    orionPrint("📤 [Orion] Sent metrics for screen: $screenName");
  }

  /// 🧠 Resume previous screen from stack (for back navigation)
  /// This RESTARTS tracking for the previous screen (for workflows where screens are finalized on navigation)
  static void resumePreviousScreen() {
    if (!OrionFlutter.isAndroid) return;

    if (_screenHistoryStack.length >= 1) {
      final previous = _screenHistoryStack.last;
      orionPrint("🔁 [Orion] Resumed tracking for previous screen: $previous");
      startTracking(previous);  // ✅ Restart tracking (for back navigation after finalize)
    } else {
      orionPrint("⚠️ [Orion] No previous screen to resume in stack");
    }
  }

  /// 🔍 Peek the second-last screen name (without modifying stack)
  static String? getLastTrackedScreen() {
    if (!OrionFlutter.isAndroid) return null;

    if (_screenHistoryStack.length >= 2) {
      return _screenHistoryStack[_screenHistoryStack.length - 2];
    } else {
      orionPrint("⚠️ [Orion] No previous screen in history stack");
      return null;
    }
  }

  /// Check if screen is currently being tracked
  static bool hasTracked(String screenName) {
    if (!OrionFlutter.isAndroid) return false;

    final exists = _screenMetrics.containsKey(screenName);
    orionPrint("🔍 [Orion] hasTracked($screenName): $exists");
    return exists;
  }

  /// Mark screen as fully drawn (for async content)
  static void markFullyDrawn(String screenName) {
    if (!OrionFlutter.isAndroid) return;

    _manualTTFDFlags[screenName] = true;
    orionPrint("🎯 [$screenName] Manual TTFD triggered");
  }

  static bool _hasManualTTFD(String screenName) {
    return _manualTTFDFlags[screenName] == true;
  }
}

class _ManualScreenMetrics {
  final String screenName;
  final Stopwatch _stopwatch = Stopwatch();

  // TTID/TTFD
  int _ttid = -1;
  int _ttfd = -1;
  bool _ttidCaptured = false;
  bool _ttfdCaptured = false;
  bool _ttfdManual = false;

  // Frame stability tracking
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 3;
  static const int _maxFrameDuration = 16;
  int? _lastFrameTime;

  bool _disposed = false;

  _ManualScreenMetrics(this.screenName);

  void begin() {
    if (!OrionFlutter.isAndroid) return;

    _stopwatch.start();

    // Start TTID tracking
    _captureTTID();

    // Start TTFD tracking
    _startTTFDTracking();

    // ✅ Start frame metrics tracking
    OrionFrameMetrics.startTracking(screenName);
  }

  void _captureTTID() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _ttidCaptured) return;

      _ttid = _stopwatch.elapsedMilliseconds;
      _ttidCaptured = true;

      orionPrint("🎨 [$screenName] TTID: $_ttid ms");
    });
  }

  void _startTTFDTracking() {
    if (OrionManualTracker._hasManualTTFD(screenName)) {
      _startManualTTFDTracking();
    } else {
      _startAutomaticTTFDTracking();
    }
  }

  void _startAutomaticTTFDTracking() {
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _startManualTTFDTracking() {
    orionPrint("⏳ [$screenName] Waiting for manual TTFD trigger...");
    _pollForManualTTFD();
  }

  void _pollForManualTTFD() {
    if (_disposed || _ttfdCaptured) return;

    if (OrionManualTracker._hasManualTTFD(screenName)) {
      _ttfd = _stopwatch.elapsedMilliseconds;
      _ttfdCaptured = true;
      _ttfdManual = true;

      orionPrint("✅ [$screenName] Manual TTFD captured: $_ttfd ms");
      return;
    }

    if (_stopwatch.elapsedMilliseconds > 10000) {
      _ttfd = _stopwatch.elapsedMilliseconds;
      _ttfdCaptured = true;
      orionPrint("⚠️ [$screenName] Manual TTFD timeout: $_ttfd ms");
      return;
    }

    Future.delayed(const Duration(milliseconds: 50), _pollForManualTTFD);
  }

  void _onFrame(Duration timestamp) {
    if (_disposed || _ttfdCaptured) return;

    final currentTime = timestamp.inMilliseconds;

    if (_lastFrameTime != null) {
      final frameDuration = currentTime - _lastFrameTime!;

      if (frameDuration <= _maxFrameDuration) {
        _stableFrameCount++;

        if (_stableFrameCount >= _requiredStableFrames) {
          _ttfd = _stopwatch.elapsedMilliseconds;
          _ttfdCaptured = true;

          orionPrint("✅ [$screenName] TTFD: $_ttfd ms (after $_requiredStableFrames stable frames)");
          return;
        }
      } else {
        if (frameDuration > 32) {
          _stableFrameCount = 0;
        }
      }
    }

    _lastFrameTime = currentTime;

    if (!_ttfdCaptured) {
      if (_stopwatch.elapsedMilliseconds > 10000) {
        _ttfd = _stopwatch.elapsedMilliseconds;
        _ttfdCaptured = true;
        orionPrint("⚠️ [$screenName] TTFD timeout: $_ttfd ms");
        return;
      }

      SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
    }
  }

  void send() {
    if (!OrionFlutter.isAndroid || _disposed) return;

    _disposed = true;

    // Wait to ensure TTFD and frame metrics are captured
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!OrionFlutter.isAndroid) return;

      if (!_ttfdCaptured) {
        _ttfd = _stopwatch.elapsedMilliseconds;
        _ttfdCaptured = true;
      }

      // ✅ Stop frame metrics tracking and get results
      final frameMetrics = OrionFrameMetrics.stopTracking(screenName);

      final networkData = OrionNetworkTracker.consumeRequestsForScreen(screenName);

      orionPrint(
          "📤 [$screenName] Sending beacon:\n"
              "   TTID: $_ttid ms, TTFD: $_ttfd ms${_ttfdManual ? ' (manual)' : ''}\n"
              "   Janky: ${frameMetrics.jankyFrames}/${frameMetrics.totalFrames} frames\n"
              "   Frozen: ${frameMetrics.frozenFrames} frames\n"
              "   Clusters: ${frameMetrics.top10Clusters.length}\n"
              "   Avg frame: ${frameMetrics.avgFrameDuration.toStringAsFixed(2)}ms\n"
              "   Worst frame: ${frameMetrics.worstFrameDuration.toStringAsFixed(2)}ms\n"
              "   Network: ${networkData.length} requests"
      );

      // ✅ Get ultra-compact beacon with shorthand names
      final frameBeacon = frameMetrics.toBeacon();

      // Pass frame metrics as separate parameter (not in network array)
      OrionFlutter.trackFlutterScreen(
        screen: screenName,
        ttid: _ttid,
        ttfd: _ttfd,
        jankyFrames: frameMetrics.jankyFrames,
        frozenFrames: frameMetrics.frozenFrames,
        network: networkData,
        frameMetrics: frameBeacon,  // ✅ Separate parameter for frame metrics
      );
    });
  }
}