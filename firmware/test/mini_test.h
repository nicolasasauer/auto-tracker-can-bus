// Kleines Test-Gerüst ohne Abhängigkeiten, damit die Tests mit jedem
// C++-Compiler laufen (PC, CI, eigener Runner).
#pragma once

#include <stdio.h>
#include <string.h>

#include <string>
#include <vector>

namespace mini_test {

struct Case {
  const char* name;
  void (*fn)();
};

inline std::vector<Case>& cases() {
  static std::vector<Case> all;
  return all;
}

inline int& failures() {
  static int n = 0;
  return n;
}

struct Register {
  Register(const char* name, void (*fn)()) { cases().push_back({name, fn}); }
};

inline std::string hex(const unsigned char* data, size_t len) {
  std::string s;
  char buf[4];
  for (size_t i = 0; i < len; ++i) {
    snprintf(buf, sizeof(buf), i == 0 ? "%02X" : " %02X", data[i]);
    s += buf;
  }
  return s;
}

inline int runAll() {
  for (const Case& c : cases()) {
    const int before = failures();
    c.fn();
    printf("%s %s\n", failures() == before ? "ok  " : "FAIL", c.name);
  }
  printf("\n%zu Tests, %d Fehler\n", cases().size(), failures());
  return failures() == 0 ? 0 : 1;
}

}  // namespace mini_test

#define TEST(name)                                         \
  static void name();                                      \
  static mini_test::Register name##_reg(#name, &name);     \
  static void name()

#define EXPECT(cond)                                                 \
  do {                                                               \
    if (!(cond)) {                                                   \
      printf("  %s:%d: erwartet: %s\n", __FILE__, __LINE__, #cond);  \
      ++mini_test::failures();                                       \
    }                                                                \
  } while (0)

#define EXPECT_EQ(a, b)                                                   \
  do {                                                                    \
    const auto va = (a);                                                  \
    const auto vb = (b);                                                  \
    if (!(va == vb)) {                                                    \
      printf("  %s:%d: %s == %s, ist %lld, erwartet %lld\n", __FILE__,    \
             __LINE__, #a, #b, (long long)va, (long long)vb);             \
      ++mini_test::failures();                                            \
    }                                                                     \
  } while (0)

#define EXPECT_HEX(data, len, expected)                                     \
  do {                                                                      \
    const std::string got = mini_test::hex((data), (len));                  \
    if (got != (expected)) {                                                \
      printf("  %s:%d:\n    ist      %s\n    erwartet %s\n", __FILE__,      \
             __LINE__, got.c_str(), (expected));                            \
      ++mini_test::failures();                                              \
    }                                                                       \
  } while (0)
