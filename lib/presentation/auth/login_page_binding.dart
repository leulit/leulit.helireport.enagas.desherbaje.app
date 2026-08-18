import 'package:get/get.dart';

import '../../core/screen_controller.dart';
import 'login_page_controller.dart';

class LoginBinding extends Bindings {
  @override
  void dependencies() {
    putScreenController<LoginPageController>(() => LoginPageController());
  }
}
