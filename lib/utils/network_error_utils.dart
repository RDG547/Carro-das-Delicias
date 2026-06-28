class NetworkErrorUtils {
  NetworkErrorUtils._();

  static bool isTransientNetworkError(Object error) {
    final message = error.toString().toLowerCase();
    const transientFragments = [
      'socketexception',
      'failed host lookup',
      'no address associated with hostname',
      'temporary failure in name resolution',
      'network is unreachable',
      'connection refused',
      'connection reset',
      'connection timed out',
      'operation timed out',
      'xmlhttprequest error',
    ];

    return transientFragments.any(message.contains);
  }
}
