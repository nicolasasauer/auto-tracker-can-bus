#include "protocol.h"

#include <string.h>

namespace can_core {
namespace protocol {

namespace {

void put16(uint8_t* p, uint16_t v) {
  p[0] = static_cast<uint8_t>(v);
  p[1] = static_cast<uint8_t>(v >> 8);
}

void put32(uint8_t* p, uint32_t v) {
  p[0] = static_cast<uint8_t>(v);
  p[1] = static_cast<uint8_t>(v >> 8);
  p[2] = static_cast<uint8_t>(v >> 16);
  p[3] = static_cast<uint8_t>(v >> 24);
}

uint16_t get16(const uint8_t* p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

uint32_t get32(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

}  // namespace

size_t monitorRecordsForMtu(uint16_t mtu) {
  if (mtu < 3 + kMonitorHeaderSize) return 0;
  const size_t payload = mtu - 3 - kMonitorHeaderSize;
  const size_t n = payload / kMonitorRecordSize;
  return n > 255 ? 255 : n;
}

size_t encodeMonitor(uint16_t seq, uint32_t time_ms, const IdReport* records,
                     size_t n, uint8_t* out, size_t cap) {
  if (n > 255) return 0;
  const size_t len = kMonitorHeaderSize + n * kMonitorRecordSize;
  if (len > cap) return 0;
  out[0] = kTypeMonitor;
  out[1] = kVersion;
  put16(out + 2, seq);
  put32(out + 4, time_ms);
  out[8] = static_cast<uint8_t>(n);
  uint8_t* p = out + kMonitorHeaderSize;
  for (size_t i = 0; i < n; ++i, p += kMonitorRecordSize) {
    const IdReport& r = records[i];
    put32(p, r.id);
    p[4] = r.dlc;
    memcpy(p + 5, r.data, 8);
    memcpy(p + 13, r.changed, 8);
    put16(p + 21, r.frames);
    put16(p + 23, r.period_ms);
  }
  return len;
}

size_t encodeStatus(const Status& s, uint8_t* out, size_t cap) {
  if (cap < kStatusSize) return 0;
  out[0] = kTypeStatus;
  out[1] = kVersion;
  out[2] = s.fw_major;
  out[3] = s.fw_minor;
  out[4] = s.fw_patch;
  out[5] = static_cast<uint8_t>(s.mode);
  out[6] = static_cast<uint8_t>(s.state);
  out[7] = static_cast<uint8_t>((s.pairing_open ? 0x01 : 0) |
                                (s.usb_host ? 0x02 : 0));
  put32(out + 8, s.uptime_s);
  put32(out + 12, s.frames_total);
  put32(out + 16, s.frames_dropped);
  put16(out + 20, s.ids_seen);
  put16(out + 22, s.supply_mv);
  return kStatusSize;
}

size_t encodeDiagnostics(const Diagnostics& d, uint8_t* out, size_t cap) {
  if (cap < kDiagnosticsSize) return 0;
  out[0] = kTypeDiagnostics;
  out[1] = kVersion;
  put16(out + 2, d.load_now_centi);
  put16(out + 4, d.load_avg_centi);
  put16(out + 6, d.load_peak_centi);
  out[8] = d.rx_error_counter;
  out[9] = d.error_flags;
  put32(out + 10, d.error_events);
  put16(out + 14, d.ring_max_fill);
  put16(out + 16, d.ring_capacity);
  out[18] = static_cast<uint8_t>(d.reset_reason);
  out[19] = 0;  // frei
  put32(out + 20, d.boot_count);
  return kDiagnosticsSize;
}

bool parseCommand(const uint8_t* data, size_t len, Command& out) {
  if (len == 0) return false;
  out = Command{};
  out.type = data[0];
  switch (data[0]) {
    case kCmdResetStats:
      return len == 1;
    case kCmdSetFilter: {
      if (len < 2) return false;
      const uint8_t n = data[1];
      if (n > 8 || len != 2 + static_cast<size_t>(n) * 8) return false;
      out.filter_count = n;
      for (uint8_t i = 0; i < n; ++i) {
        out.filters[i].id = get32(data + 2 + i * 8);
        out.filters[i].mask = get32(data + 6 + i * 8);
      }
      return true;
    }
    case kCmdSetInterval: {
      if (len != 3) return false;
      const uint16_t ms = get16(data + 1);
      if (ms < kIntervalMinMs || ms > kIntervalMaxMs) return false;
      out.interval_ms = ms;
      return true;
    }
    default:
      return false;
  }
}

}  // namespace protocol
}  // namespace can_core
