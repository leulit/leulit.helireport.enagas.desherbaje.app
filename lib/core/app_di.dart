import 'package:get/get.dart';
import 'services/connectivity_service.dart';
import 'services/gasoductos_service.dart';
import 'services/gps_service.dart';
import '../data/network/network_service.dart';

class AppDI {
  static Future<void> init() async {
    await Get.putAsync<ConnectivityService>(
      () async => ConnectivityService(),
      permanent: true,
    );
    await Get.putAsync<NetworkService>(
      () async => NetworkService(),
      permanent: true,
    );
    Get.put<GpsService>(GpsService(), permanent: true);
    Get.put<GasoductosService>(GasoductosService(), permanent: true);
  }
}
