#include "id_monitor.h"

#include <string.h>

namespace can_core {

IdMonitor::Slot* IdMonitor::find(uint32_t id) {
  for (size_t i = 0; i < count_; ++i) {
    if (slots_[i].id == id) return &slots_[i];
  }
  return nullptr;
}

void IdMonitor::onFrame(const CanFrame& frame, uint32_t now_ms) {
  ++frames_total_;
  const uint8_t dlc = frame.dlc > 8 ? 8 : frame.dlc;
  uint8_t data[8] = {};
  memcpy(data, frame.data, dlc);

  Slot* slot = find(frame.id);
  if (slot == nullptr) {
    if (count_ >= kCapacity) {
      ++frames_untracked_;
      return;
    }
    slot = &slots_[count_++];
    memset(slot, 0, sizeof(*slot));
    slot->id = frame.id;
    slot->dlc = dlc;
    memcpy(slot->data, data, 8);
    slot->pending = 1;
    slot->last_ms = now_ms;
    return;
  }

  for (int i = 0; i < 8; ++i) {
    slot->changed[i] |= static_cast<uint8_t>(slot->data[i] ^ data[i]);
  }
  memcpy(slot->data, data, 8);
  slot->dlc = dlc;

  const uint32_t dt = now_ms - slot->last_ms;
  slot->period_ms = slot->period_ms == 0 ? dt : (slot->period_ms * 7 + dt) / 8;
  slot->last_ms = now_ms;
  ++slot->pending;
}

bool IdMonitor::hasPending() const {
  for (size_t i = 0; i < count_; ++i) {
    if (slots_[i].pending > 0) return true;
  }
  return false;
}

size_t IdMonitor::collect(IdReport* out, size_t max) {
  size_t n = 0;
  for (size_t step = 0; step < count_ && n < max; ++step) {
    Slot& slot = slots_[(cursor_ + step) % count_];
    if (slot.pending == 0) continue;
    IdReport& r = out[n++];
    r.id = slot.id;
    r.dlc = slot.dlc;
    memcpy(r.data, slot.data, 8);
    memcpy(r.changed, slot.changed, 8);
    r.frames = slot.pending > 0xFFFF ? 0xFFFF : static_cast<uint16_t>(slot.pending);
    r.period_ms = slot.period_ms > 0xFFFF ? 0xFFFF : static_cast<uint16_t>(slot.period_ms);
    slot.pending = 0;
    memset(slot.changed, 0, 8);
    if (n == max) {
      cursor_ = (cursor_ + step + 1) % count_;
      return n;
    }
  }
  return n;
}

void IdMonitor::reset() {
  count_ = 0;
  cursor_ = 0;
  frames_total_ = 0;
  frames_untracked_ = 0;
}

}  // namespace can_core
