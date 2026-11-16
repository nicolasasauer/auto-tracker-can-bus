/// UUIDs des GATT-Dienstes (docs/CAN-BLE-PROTOKOLL.md, Kapitel 1).
/// Müssen zu firmware/can_logger/src/ble_link.cpp passen.
abstract final class CanLinkUuids {
  static const service = 'e7cec12e-2ee5-4284-ad6a-0703c3a17296';
  static const status = 'ee9f0489-a96e-4e62-b798-0f9d1a820508';
  static const monitor = '386e5ff1-e339-49e5-bd0d-1d6deb060a3b';
  static const control = 'd12d8602-4d4b-456b-a672-ff97e3b2a4ca';
  static const diagnostics = '73314b58-7edf-4e94-b961-75569ead600f';
}
