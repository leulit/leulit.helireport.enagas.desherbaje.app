import 'package:get/get.dart';
import '../../core/services/connectivity_service.dart';
import 'segmento_data_provider.dart';
import 'segmento_data_provider_online.dart';
import 'segmento_data_provider_offline.dart';

class SegmentoDataProviderFactory {
  static SegmentoDataProvider create() {
    final connectivity = Get.find<ConnectivityService>();
    return SegmentoDataProviderOnline();
    return connectivity.isConnected
        ? SegmentoDataProviderOnline()
        : SegmentoDataProviderOffline();
  }
}
