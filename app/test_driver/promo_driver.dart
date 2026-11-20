// The host side of the promo tour (integration_test/promo_tour.dart, run by
// tool/promo_capture.sh). The tour writes its own screenshots and scene
// timings from inside the app, so all this does is wait for it to finish.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(timeout: const Duration(minutes: 15));
