import 'package:get/get.dart';
import '../controllers/torbox_controller.dart';

class TorBoxBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<TorBoxController>(() => TorBoxController());
  }
}
