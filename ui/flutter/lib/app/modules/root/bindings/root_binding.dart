import 'package:get/get.dart';

import '../../torbox/controllers/torbox_controller.dart';
import '../controllers/root_controller.dart';

class RootBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<RootController>(() => RootController(), fenix: true);
    // Register TorBoxController early so it is available when deep links
    // arrive on cold start (before the TorBox page is ever visited).
    Get.lazyPut<TorBoxController>(() => TorBoxController(), fenix: true);
  }
}
