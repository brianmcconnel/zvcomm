/// Identifies a physical or logical short-range link technology.
enum TransportKind {
  /// Bluetooth Low Energy GATT / advertising.
  ble,

  /// Near Field Communication (NDEF / peer-to-peer).
  nfc,

  /// Wi-Fi Direct, Aware, Multipeer, SoftAP, or similar.
  wifi,

  /// Ultra-wideband (future).
  uwb,

  /// Long-range radio (future, e.g. LoRa).
  lora,

  /// In-process mock for tests and the simulator.
  mock,

  /// Custom / user-supplied adapter.
  custom,
}

/// Relative power / throughput hints used by adaptive link selection.
extension TransportKindPrefs on TransportKind {
  /// Higher is preferred when bandwidth matters (Wi-Fi > BLE > NFC).
  int get bandwidthRank => switch (this) {
        TransportKind.wifi => 100,
        TransportKind.uwb => 80,
        TransportKind.ble => 40,
        TransportKind.lora => 20,
        TransportKind.nfc => 10,
        TransportKind.mock => 50,
        TransportKind.custom => 30,
      };

  /// Higher means more power-hungry.
  int get powerCost => switch (this) {
        TransportKind.wifi => 80,
        TransportKind.uwb => 50,
        TransportKind.ble => 25,
        TransportKind.lora => 40,
        TransportKind.nfc => 15,
        TransportKind.mock => 0,
        TransportKind.custom => 40,
      };
}
