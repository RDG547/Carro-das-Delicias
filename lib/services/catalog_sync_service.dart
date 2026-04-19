import 'package:flutter/foundation.dart';

class CatalogSyncService extends ChangeNotifier {
  CatalogSyncService._();

  static final CatalogSyncService instance = CatalogSyncService._();

  int _revision = 0;

  int get revision => _revision;

  void notifyCatalogChanged() {
    _revision++;
    notifyListeners();
  }
}
