class MainNavigationService {
  static const int cartPageIndex = 4;
  static const int ordersPageIndex = 2;

  static void Function(int)? _navigateToPageDirect;

  static void attach(void Function(int) navigateToPageDirect) {
    _navigateToPageDirect = navigateToPageDirect;
  }

  static void detach() {
    _navigateToPageDirect = null;
  }

  static bool navigateToPage(int pageIndex) {
    final callback = _navigateToPageDirect;
    if (callback == null) {
      return false;
    }

    callback(pageIndex);
    return true;
  }

  static bool navigateToCart() {
    return navigateToPage(cartPageIndex);
  }

  static bool navigateToOrders() {
    return navigateToPage(ordersPageIndex);
  }
}
