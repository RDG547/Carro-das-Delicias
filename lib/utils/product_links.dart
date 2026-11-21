class ProductLinks {
  static const publicBase = String.fromEnvironment('PRODUCT_SHARE_BASE_URL',
      defaultValue: 'https://carrodasdelicias.vercel.app');
  static Uri forProduct(Object id) => Uri.parse(publicBase).resolve('/produto/$id');

  static String? productIdFrom(Uri uri) {
    String? id;
    if (uri.scheme == 'carrodasdelicias') {
      if (uri.host == 'produto' && uri.pathSegments.length == 1) id = uri.pathSegments.first;
      if (uri.host.isEmpty && uri.pathSegments.length == 2 && uri.pathSegments.first == 'produto') id = uri.pathSegments.last;
    } else if (uri.scheme == 'https' &&
        {Uri.parse(publicBase).host, 'carrodasdelicias.vercel.app', 'carrodasdelicias.app'}.contains(uri.host) &&
        uri.pathSegments.length == 2 && uri.pathSegments.first == 'produto') {
      id = uri.pathSegments.last;
    }
    final number = int.tryParse(id ?? '');
    return number != null && number > 0 ? number.toString() : null;
  }
}
