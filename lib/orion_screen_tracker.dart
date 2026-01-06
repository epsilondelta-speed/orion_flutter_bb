import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'orion_flutter.dart';
import 'orion_network_tracker.dart';
import 'orion_logger.dart';
import 'orion_frame_metrics.dart';

/// RouteObserver with comprehensive frame tracking
///
/// Features:
/// - Accurate TTID/TTFD with frame stability
/// - Real janky/frozen frame detection
/// - Top 10 jank clusters with ultra-compact beacon
/// - Frozen frames tracked separately
/// - Waterfall UI ready (timestamps included)
///
/// Usage:
/// ```dart
/// MaterialApp(
///   navigatorObservers: [OrionScreenTracker()],
/// )
/// ```
class OrionScreenTracker extends RouteObserver<PageRoute<dynamic>> {
  final Map<String, _ScreenMetrics> _screenMetrics = {};

  // Manual TTFD support
  static final Map<String, bool> _manualTTFDFlags = {};

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (!OrionFlutter.isAndroid) return;

    _finalizeTracking(previousRoute);
    _updateCurrentScreen(route);
    _startTracking(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (!OrionFlutter.isAndroid) return;

    _finalizeTracking(oldRoute);
    _startTracking(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (!OrionFlutter.isAndroid) return;

    _updateCurrentScreen(previousRoute);
    _finalizeTracking(route);
  }

  void _updateCurrentScreen(Route? route) {
    if (!OrionFlutter.isAndroid) return;

    if (route is PageRoute) {
      final screenName = route.settings.name ?? route.runtimeType.toString();
      OrionNetworkTracker.setCurrentScreen(screenName);
      orionPrint("OrionNetworkTracker currentScreenName set to $screenName");
    }
  }

  void _startTracking(Route? route) {
    if (!OrionFlutter.isAndroid) return;

    if (route is PageRoute) {
      final screenName = route.settings.name ?? route.runtimeType.toString();
      final metrics = _ScreenMetrics(screenName);
      _screenMetrics[screenName] = metrics;
      metrics.begin();
    }
  }

  void _finalizeTracking(Route? route) {
    if (!OrionFlutter.isAndroid) return;

    if (route is PageRoute) {
      final screenName = route.settings.name ?? route.runtimeType.toString();
      final metrics = _screenMetrics.remove(screenName);
      metrics?.send();

      _manualTTFDFlags.remove(screenName);
    }
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

class _ScreenMetrics {
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

  _ScreenMetrics(this.screenName);

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
    if (OrionScreenTracker._hasManualTTFD(screenName)) {
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

    if (OrionScreenTracker._hasManualTTFD(screenName)) {
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