/// Bluetooth LE transport adapter for ZVComm.
///
/// Uses [bluetooth_low_energy] (MIT) for central scanning/connect and
/// peripheral advertising/GATT server on supported platforms.
library;

export 'src/ble_transport.dart';
export 'src/ble_connection.dart';
