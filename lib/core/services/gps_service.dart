import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class GpsService extends GetxService {
  final _hasPermission = false.obs;
  bool get hasPermission => _hasPermission.value;

  @override
  void onInit() {
    super.onInit();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.locationWhenInUse.status;
    _hasPermission.value = status.isGranted;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    _hasPermission.value = status.isGranted;
    return status.isGranted;
  }
}
