part of internet_connection_checker_plus;

/// This is a singleton that can be accessed like a regular constructor
/// i.e. [InternetConnectionCheckerPlus()] always returns the same instance.
class InternetConnectionCheckerPlus {
  /// This is a singleton that can be accessed like a regular constructor
  /// i.e. InternetConnectionCheckerPlus() always returns the same instance.
  factory InternetConnectionCheckerPlus() => _instance;

  /// Creates an instance of the [InternetConnectionCheckerPlus]. This can be
  /// registered in any dependency injection framework with custom values for
  /// the [checkTimeout] and [checkInterval].
  InternetConnectionCheckerPlus.createInstance({
    this.checkTimeout = defaultTimeout,
    this.checkInterval = defaultInterval,
    List<AddressCheckOptions>? addresses,
  }) {
    this.addresses = addresses ??
        _defaultAddresses
            .map((options) => AddressCheckOptions(
                  options.uri,
                  headers: options.headers,
                  timeout: checkTimeout,
                ))
            .toList();

    // immediately perform an initial check so we know the last status?
    // connectionStatus.then((status) => _lastStatus = status);

    // start sending status updates to onStatusChange when there are listeners
    // (emits only if there's any change since the last status update)
    _statusController.onListen = () {
      _maybeEmitStatusUpdate();
    };

    // stop sending status updates when no one is listening
    _statusController.onCancel = () {
      _timerHandle?.cancel();
      _lastStatus = null; // reset last status
    };
  }

  /// Default timeout is 4 seconds.
  ///
  /// Timeout is the number of seconds before a request is dropped
  /// and an address is considered unreachable
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Default interval is 5 seconds
  ///
  /// Interval is the time between automatic checks
  static const Duration defaultInterval = Duration(seconds: 5);

  static final List<AddressCheckOptions> _defaultAddresses = [
    AddressCheckOptions(
      Uri.parse('https://ya.ru'),
    ),
    AddressCheckOptions(
      Uri.parse('https://google.com'),
    ),
  ];

  late List<AddressCheckOptions> _addresses;

  /// A list of internet addresses (with port and timeout) to ping.
  ///
  /// These should be globally available destinations.
  /// Default is [_defaultAddresses].
  ///
  /// When [hasConnection] or [connectionStatus] is called,
  /// this utility class tries to ping every address in this list.
  ///
  /// The provided addresses should be good enough to test for data connection
  /// but you can, of course, supply your own.
  ///
  /// See [AddressCheckOptions] for more info.
  List<AddressCheckOptions> get addresses => _addresses;

  set addresses(List<AddressCheckOptions> value) {
    _addresses = List<AddressCheckOptions>.unmodifiable(value);
    _maybeEmitStatusUpdate();
  }

  static final InternetConnectionCheckerPlus _instance =
      InternetConnectionCheckerPlus.createInstance();

  /// Ping a single address. See [AddressCheckOptions] for
  /// info on the accepted argument.
  Future<AddressCheckResult> isHostReachable(
    AddressCheckOptions options,
  ) async {
    try {
      http.Response? response = await http
          .get(
            options.uri,
            headers: options.headers,
          )
          .timeout(options.timeout);

      if (response.statusCode == 200) {
        return AddressCheckResult(
          options,
          isSuccess: true,
        );
      } else {
        return AddressCheckResult(
          options,
          isSuccess: false,
        );
      }
    } on Exception {
      return AddressCheckResult(
        options,
        isSuccess: false,
      );
    }
  }

  /// Initiates a request to each address in [addresses].
  /// If at least one of the addresses is reachable
  /// we assume an internet connection is available and return `true`.
  /// `false` otherwise.
  Future<bool> get hasConnection async {
    final Completer<bool> result = Completer<bool>();
    int length = addresses.length;

    for (final AddressCheckOptions addressOptions in addresses) {
      // ignore: unawaited_futures
      isHostReachable(addressOptions).then(
        (AddressCheckResult request) {
          length -= 1;
          if (!result.isCompleted) {
            if (request.isSuccess) {
              result.complete(true);
            } else if (length == 0) {
              result.complete(false);
            }
          }
        },
      );
    }

    return result.future;
  }

  /// Initiates a request to each address in [addresses].
  /// If at least one of the addresses is reachable
  /// we assume an internet connection is available and return
  /// [InternetConnectionStatus.connected].
  /// [InternetConnectionStatus.disconnected] otherwise.
  Future<InternetConnectionStatus> get connectionStatus async {
    return await hasConnection
        ? InternetConnectionStatus.connected
        : InternetConnectionStatus.disconnected;
  }

  /// The interval between periodic checks. Periodic checks are
  /// only made if there's an attached listener to [onStatusChange].
  /// If that's the case [onStatusChange] emits an update only if
  /// there's change from the previous status.
  ///
  /// Defaults to [defaultInterval] (5 seconds).
  final Duration checkInterval;

  /// The timeout period before a check request is dropped and an address is
  /// considered unreachable.
  ///
  /// Defaults to [defaultTimeout] (4 seconds).
  final Duration checkTimeout;

  // Checks the current status, compares it with the last and emits
  // an event only if there's a change and there are attached listeners
  //
  // If there are listeners, a timer is started which runs this function again
  // after the specified time in 'checkInterval'
  Future<void> _maybeEmitStatusUpdate([
    Timer? timer,
  ]) async {
    // just in case
    _timerHandle?.cancel();
    timer?.cancel();

    final InternetConnectionStatus currentStatus = await connectionStatus;

    // only send status update if last status differs from current
    // and if someone is actually listening
    if (_lastStatus != currentStatus && _statusController.hasListener) {
      _statusController.add(currentStatus);
    }

    // start new timer only if there are listeners
    if (!_statusController.hasListener) return;
    _timerHandle = Timer(checkInterval, _maybeEmitStatusUpdate);

    // update last status
    _lastStatus = currentStatus;
  }

  // _lastStatus should only be set by _maybeEmitStatusUpdate()
  // and the _statusController's.onCancel event handler
  InternetConnectionStatus? _lastStatus;
  Timer? _timerHandle;

  // controller for the exposed 'onStatusChange' Stream
  final StreamController<InternetConnectionStatus> _statusController =
      StreamController<InternetConnectionStatus>.broadcast();

  /// Subscribe to this stream to receive events whenever the
  /// [InternetConnectionStatus] changes. When a listener is attached
  /// a check is performed immediately and the status ([InternetConnectionStatus])
  /// is emitted. After that a timer starts which performs
  /// checks with the specified interval - [checkInterval].
  /// Default is [defaultInterval].
  ///
  /// *As long as there's an attached listener, checks are being performed,
  /// so remember to dispose of the subscriptions when they're no longer needed.*
  ///
  /// Example:
  ///
  /// ```dart
  /// var listener = InternetConnectionCheckerPlus().onStatusChange.listen((status) {
  ///   switch(status) {
  ///     case InternetConnectionStatus.connected:
  ///       print('Data connection is available.');
  ///       break;
  ///     case InternetConnectionStatus.disconnected:
  ///       print('You are disconnected from the internet.');
  ///       break;
  ///   }
  /// });
  /// ```
  ///
  /// *Note: Remember to dispose of any listeners,
  /// when they're not needed anymore,
  /// e.g. in a* `StatefulWidget`'s *dispose() method*
  ///
  /// ```dart
  /// ...
  /// @override
  /// void dispose() {
  ///   listener.cancel();
  ///   super.dispose();
  /// }
  /// ...
  /// ```
  ///
  /// For as long as there's an attached listener, requests are
  /// being made with an interval of `checkInterval`. The timer stops
  /// when an automatic check is currently executed, so this interval
  /// is a bit longer actually (the maximum would be `checkInterval` +
  /// the maximum timeout for an address in `addresses`). This is by design
  /// to prevent multiple automatic calls to `connectionStatus`, which
  /// would wreck havoc.
  ///
  /// You can, of course, override this behavior by implementing your own
  /// variation of time-based checks and calling either `connectionStatus`
  /// or `hasConnection` as many times as you want.
  ///
  /// When all the listeners are removed from `onStatusChange`, the internal
  /// timer is cancelled and the stream does not emit events.
  Stream<InternetConnectionStatus> get onStatusChange => _statusController.stream;

  /// Returns true if there are any listeners attached to [onStatusChange]
  bool get hasListeners => _statusController.hasListener;

  /// Alias for [hasListeners]
  bool get isActivelyChecking => _statusController.hasListener;
}
