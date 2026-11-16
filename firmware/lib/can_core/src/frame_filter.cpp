#include "frame_filter.h"

#include "can_frame.h"

namespace can_core {

bool FrameFilter::add(uint32_t id, uint32_t mask) {
  if (count_ >= kMaxEntries) return false;
  entries_[count_++] = {id & ~kRtrFlag, mask};
  return true;
}

bool FrameFilter::accepts(uint32_t id) const {
  if (count_ == 0) return true;
  const uint32_t key = id & ~kRtrFlag;
  for (size_t i = 0; i < count_; ++i) {
    if ((key & entries_[i].mask) == (entries_[i].id & entries_[i].mask)) {
      return true;
    }
  }
  return false;
}

}  // namespace can_core
