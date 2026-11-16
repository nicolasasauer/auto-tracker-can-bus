#include "ble_link.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "config.h"
#include "elapsed.h"

namespace ble_link {
namespace {

constexpr const char* kServiceUuid = "e7cec12e-2ee5-4284-ad6a-0703c3a17296";
constexpr const char* kStatusUuid = "ee9f0489-a96e-4e62-b798-0f9d1a820508";
constexpr const char* kMonitorUuid = "386e5ff1-e339-49e5-bd0d-1d6deb060a3b";
constexpr const char* kControlUuid = "d12d8602-4d4b-456b-a672-ff97e3b2a4ca";
constexpr const char* kDiagnosticsUuid = "73314b58-7edf-4e94-b961-75569ead600f";

constexpr uint16_t kNoConn = 0xFFFF;

can_core::PairingWindow* g_window = nullptr;
NimBLEServer* g_server = nullptr;
NimBLECharacteristic* g_status = nullptr;
NimBLECharacteristic* g_monitor = nullptr;
NimBLECharacteristic* g_diagnostics = nullptr;
QueueHandle_t g_commands = nullptr;

// Werden im BLE-Task geschrieben und in loop() gelesen.
volatile uint16_t g_conn = kNoConn;
volatile bool g_secure = false;
volatile bool g_pairing_rejected = false;
volatile uint16_t g_mtu = 23;
volatile uint32_t g_connected_ms = 0;

void dropConnection(uint16_t handle) {
  if (g_server != nullptr && handle != kNoConn) g_server->disconnect(handle);
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    if (g_conn != kNoConn) {
      // Immer nur eine App zugleich.
      server->disconnect(info.getConnHandle());
      return;
    }
    g_conn = info.getConnHandle();
    g_secure = false;
    g_pairing_rejected = false;
    g_mtu = 23;
    g_connected_ms = millis();
    // Verschlüsselung sofort anstoßen: gekoppelte Handys sind dann ohne
    // Eingabe verbunden, neue müssen den Code eingeben.
    NimBLEDevice::startSecurity(info.getConnHandle());
  }

  void onDisconnect(NimBLEServer* /*server*/, NimBLEConnInfo& info,
                    int /*reason*/) override {
    if (info.getConnHandle() == g_conn) {
      g_conn = kNoConn;
      g_secure = false;
    }
    NimBLEDevice::startAdvertising();
  }

  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    if (info.getConnHandle() == g_conn) g_mtu = mtu;
  }

  uint32_t onPassKeyDisplay() override {
    const auto decision = g_window->onPairingRequest(
        millis(), static_cast<uint8_t>(NimBLEDevice::getNumBonds()),
        esp_random());
    g_pairing_rejected = !decision.allow;
    return decision.passkey;
  }

  void onAuthenticationComplete(NimBLEConnInfo& info) override {
    if (!info.isEncrypted() || !info.isAuthenticated() || g_pairing_rejected) {
      // Neue Kopplung außerhalb des Fensters (oder ohne Passkey): nicht
      // behalten, Verbindung trennen.
      if (g_pairing_rejected) NimBLEDevice::deleteBond(info.getIdAddress());
      dropConnection(info.getConnHandle());
      return;
    }
    if (info.getConnHandle() == g_conn) g_secure = true;
  }
};

class ControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& info) override {
    if (!g_secure || info.getConnHandle() != g_conn) return;
    const NimBLEAttValue value = chr->getValue();
    can_core::protocol::Command cmd;
    if (can_core::protocol::parseCommand(value.data(), value.length(), cmd)) {
      xQueueSend(g_commands, &cmd, 0);
    }
  }
};

}  // namespace

void begin(can_core::PairingWindow* window) {
  g_window = window;
  g_commands = xQueueCreate(4, sizeof(can_core::protocol::Command));

  NimBLEDevice::init(config::kDeviceName);
  NimBLEDevice::setMTU(247);
  // LE Secure Connections, Bonding, Schutz gegen Zwischenschalten (MITM).
  // Der Leser „zeigt“ den Code an: auf der seriellen Konsole.
  NimBLEDevice::setSecurityAuth(true, true, true);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);

  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = g_server->createService(kServiceUuid);
  const uint32_t secure_read = NIMBLE_PROPERTY::READ |
                               NIMBLE_PROPERTY::READ_ENC |
                               NIMBLE_PROPERTY::READ_AUTHEN;
  g_status = service->createCharacteristic(
      kStatusUuid, secure_read | NIMBLE_PROPERTY::NOTIFY);
  g_monitor = service->createCharacteristic(
      kMonitorUuid, secure_read | NIMBLE_PROPERTY::NOTIFY);
  g_diagnostics = service->createCharacteristic(
      kDiagnosticsUuid, secure_read | NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* control = service->createCharacteristic(
      kControlUuid, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC |
                        NIMBLE_PROPERTY::WRITE_AUTHEN);
  control->setCallbacks(new ControlCallbacks());

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(kServiceUuid);
  // Der Name passt nicht mehr ins Werbepaket (128-Bit-UUID), er kommt in die
  // Scan-Antwort.
  NimBLEAdvertisementData scan_response;
  scan_response.setName(config::kDeviceName);
  adv->setScanResponseData(scan_response);
  NimBLEDevice::startAdvertising();
}

void poll(uint32_t now_ms) {
  const uint16_t conn = g_conn;
  // elapsedMs statt Subtraktion: g_connected_ms setzt der BLE-Task und kann
  // jünger sein als das now_ms der Hauptschleife. Die Subtraktion liefe dann
  // über und trennte eine frische Verbindung sofort.
  if (conn != kNoConn && !g_secure &&
      can_core::elapsedMs(now_ms, g_connected_ms) > config::kAuthTimeoutMs) {
    dropConnection(conn);
  }
}

bool secureClientConnected() { return g_conn != kNoConn && g_secure; }

size_t monitorRecordCapacity() {
  return can_core::protocol::monitorRecordsForMtu(g_mtu);
}

void sendMonitor(const uint8_t* data, size_t len) {
  if (!secureClientConnected()) return;
  g_monitor->setValue(data, len);
  g_monitor->notify();
}

void updateStatus(const uint8_t* data, size_t len) {
  g_status->setValue(data, len);
  if (secureClientConnected()) g_status->notify();
}

void updateDiagnostics(const uint8_t* data, size_t len) {
  g_diagnostics->setValue(data, len);
  if (secureClientConnected()) g_diagnostics->notify();
}

bool takeCommand(can_core::protocol::Command& out) {
  return g_commands != nullptr && xQueueReceive(g_commands, &out, 0) == pdTRUE;
}

int bondCount() { return NimBLEDevice::getNumBonds(); }

void deleteAllBonds() {
  NimBLEDevice::deleteAllBonds();
  dropConnection(g_conn);
}

}  // namespace ble_link
