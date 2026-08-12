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

// --- file ---
uint8_t* glauk_read_file(const char* path, size_t* out_len);
bool     glauk_write_file(const char* path, const uint8_t* data, size_t len);
int64_t  glauk_file_mtime_ms(const char* path);

// --- notes ---
// root 以下の .md を改行区切りの相対パスで返す(NUL終端ではない)。
// 失敗時は NULL。解放は glauk_free_buffer。
uint8_t* glauk_notes_scan(const char* root, size_t* out_len);

// --- 共通 ---
void glauk_free_buffer(uint8_t* ptr, size_t len);
bool glauk_check_leaks(void);

#endif // GLAUK_H
