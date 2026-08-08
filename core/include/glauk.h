#ifndef GLAUK_H
#define GLAUK_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

const char* glauk_ping(void);

// --- markdown ---
typedef struct {
    uint32_t start;   // UTF-16 コードユニット単位
    uint32_t len;
    uint8_t  kind;
} GlaukSpan;

GlaukSpan* glauk_parse_spans(const uint8_t* text, size_t text_len, size_t* out_count);
void glauk_free_spans(GlaukSpan* spans, size_t count);

// --- 共通 ---
void glauk_free_buffer(uint8_t* ptr, size_t len);
bool glauk_check_leaks(void);

#endif // GLAUK_H
