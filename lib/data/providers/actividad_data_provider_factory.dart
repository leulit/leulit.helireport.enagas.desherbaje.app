import 'package:get/get.dart';
import '../../core/services/connectivity_service.dart';
import 'actividad_data_provider.dart';
import 'actividad_data_provider_online.dart';
import 'actividad_data_provider_offline.dart';

class ActividadDataProviderFactory {
  static ActividadDataProvider create() {
    final connectivity = Get.find<ConnectivityService>();
    return ActividadDataProviderOnline();
    return connectivity.isConnected
        ? ActividadDataProviderOnline()
        : ActividadDataProviderOffline();
  }
}
