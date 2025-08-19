/// OrionNetworkTracker
///
/// Tracks network requests per screen (used by OrionDioInterceptor).
/// Make sure to always call `OrionNetworkTracker.setCurrentScreen(screenName)`
/// when screen changes (OrionScreenTracker already handles this).


class OrionNetworkTracker {
  static final Map<String, List<Map<String, dynamic>>> _screenRequests = {};
  static String? currentScreenName;

  /// Set the current screen name (e.g., in RouteObserver)
  static void setCurrentScreen(String screenName) {
    currentScreenName = screenName;
  }

  /// Add a request associated with a screen
  static void addRequest(String screen, Map<String, dynamic> request) {
    if (!_screenRequests.containsKey(screen)) {
      _screenRequests[screen] = [];
    }
    _screenRequests[screen]!.add(request);
  }

  /// Consume and return requests for a screen (clears after return)
  static List<Map<String, dynamic>> consumeRequestsForScreen(String screen) {
    final requests = _screenRequests.remove(screen);
    return requests ?? [];
  }

  /// Clear all stored requests (optional cleanup)
  static void clearAll() {
    _screenRequests.clear();
  }
}
