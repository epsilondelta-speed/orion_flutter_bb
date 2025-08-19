import 'package:flutter/material.dart';
import 'orion_flutter.dart';
import 'orion_network_tracker.dart';
import 'orion_logger.dart';

/// A RouteObserver that tracks screen metrics (TTID, TTFD, janky, frozen) per Flutter screen
class OrionScreenTracker extends RouteObserver<PageRoute<dynamic>> {
  final Map<String, _ScreenMetrics> _screenMetrics = {};

  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);

    // ✅ Send previous screen metrics BEFORE starting new screen
    _finalizeTracking(previousRoute);

    _updateCurrentScreen(route);
    _startTracking(route);

  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _startTracking(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _updateCurrentScreen(previousRoute);
    _finalizeTracking(route);
  }

  void _updateCurrentScreen(Route? route) {
    if (route is PageRoute) {
      final screenName = route.settings.name ?? route.runtimeType.toString();
      OrionNetworkTracker.setCurrentScreen(screenName);
      orionPrint("OrionNetworkTracker currentScreenName set to $screenName");
    }
  }

  void _startTracking(Route? route) {
    if (route is PageRoute) {
      final screenName = route.settings.name ?? route.runtimeType.toString();
      final metrics = _ScreenMetrics(screenName);
      _screenMetrics[screenName] = metrics;
      metrics.begin();
    }
  }

  void _finalizeTracking(Route? route) {
    if (route is PageRoute) {
      final screenName = route.settings.name ?? route.runtimeType.toString();
      final metrics = _screenMetrics.remove(screenName);
      metrics?.send();
    }
  }


}

class _ScreenMetrics {
  final String screenName;
  final Stopwatch _stopwatch = Stopwatch();
  int _ttid = -1;
  bool _ttfdCaptured = false;

  _ScreenMetrics(this.screenName);

  void begin() {
    _stopwatch.start();

    // Capture TTID: first frame render complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ttid = _stopwatch.elapsedMilliseconds;
      debugPrint("📏 [$screenName] TTID: $_ttid ms");
    });

    // Capture TTFD, Janky, Frozen after layout stabilizes
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (_ttfdCaptured) return;
      _ttfdCaptured = true;

      Future.delayed(const Duration(milliseconds: 500), () {
        final ttfd = _stopwatch.elapsedMilliseconds;
        final janky = _mockJankyFrames();
        final frozen = _mockFrozenFrames();

        // Save for later if needed in send()
        _ttfdFinal = ttfd;
        _jankyFinal = janky;
        _frozenFinal = frozen;
      });
    });
  }

  int _ttfdFinal = -1;
  int _jankyFinal = 0;
  int _frozenFinal = 0;

  void send() {
    final networkData = OrionNetworkTracker.consumeRequestsForScreen(screenName);

    OrionFlutter.trackFlutterScreen(
      screen: screenName,
      ttid: _ttid,
      ttfd: _ttfdFinal,
      jankyFrames: _jankyFinal,
      frozenFrames: _frozenFinal,
      network: networkData,
    );
  }

  int _mockJankyFrames() => 0;
  int _mockFrozenFrames() => 0;
}