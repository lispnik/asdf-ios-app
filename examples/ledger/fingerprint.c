/* fingerprint.c -- one C function, linked into the app as a static library.
 *
 * FNV-1a, 64 bits, of a string: a fingerprint for each ledger entry, shown
 * beside it.  Small on purpose.  The point is the path it takes: build.sh
 * compiles this with clang for each platform into libfingerprint.a, the
 * .asd names that archive in :BUNDLE-STATIC-LIBRARIES, and Lisp calls it
 * through the dynamic FFI like any other C function in the process. */

#include <stdint.h>

uint64_t fingerprint(const char *text)
{
  uint64_t hash = 14695981039346656037ULL;
  for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
    hash ^= *p;
    hash *= 1099511628211ULL;
  }
  return hash;
}
