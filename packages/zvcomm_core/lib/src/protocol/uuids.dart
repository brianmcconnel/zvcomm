/// Well-known identifiers for ZVComm mesh transports.
///
/// BLE uses 128-bit UUIDs in the form below. NFC uses the URI / MIME type.
/// Wi-Fi SoftAP fallback uses the UDP discovery magic + TCP port.
abstract final class ZvcommProtocol {
  /// Primary mesh GATT service.
  static const String bleServiceUuid =
      '6b7a0001-5e2d-4f3a-9c1b-8d4e2f0a1b2c';

  /// Central → peripheral data (write / write-without-response).
  static const String bleRxCharacteristicUuid =
      '6b7a0002-5e2d-4f3a-9c1b-8d4e2f0a1b2c';

  /// Peripheral → central data (notify).
  static const String bleTxCharacteristicUuid =
      '6b7a0003-5e2d-4f3a-9c1b-8d4e2f0a1b2c';

  /// Local identity (read): UTF-8 "id|displayName".
  static const String bleIdentityCharacteristicUuid =
      '6b7a0004-5e2d-4f3a-9c1b-8d4e2f0a1b2c';

  /// Company ID used in manufacturer-specific advertisement data (unofficial).
  static const int bleManufacturerId = 0x5a56; // 'ZV'

  /// NFC NDEF MIME type for bootstrap records.
  static const String nfcMimeType = 'application/x-zvcomm';

  /// NFC well-known URI scheme prefix for pairing payloads.
  static const String nfcUriPrefix = 'zvcomm://peer/';

  /// UDP discovery magic for desktop SoftAP / LAN fallback.
  static const String lanMagic = 'ZVCOMM1';

  /// Default TCP port for LAN SoftAP fallback mesh links.
  static const int lanTcpPort = 37251;

  /// Default UDP discovery port.
  static const int lanUdpPort = 37250;
}
