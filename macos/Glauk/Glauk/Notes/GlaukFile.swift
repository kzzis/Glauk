// GlaukFile.swift
import Foundation
import GlaukCore

enum GlaukFile {
    static func read(path: String) -> String? {
        var len = 0
        guard let ptr = path.withCString({ glauk_read_file($0, &len) }) else { return nil }
        defer { glauk_free_buffer(ptr, len) }
        return String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF8.self)
    }

    static func write(path: String, contents: String) -> Bool {
        let bytes = Array(contents.utf8)
        return path.withCString { cpath in
            bytes.withUnsafeBufferPointer { buf in
                glauk_write_file(cpath, buf.baseAddress, buf.count)
            }
        }
    }

    static func mtimeMs(path: String) -> Int64? {
        let v = path.withCString { glauk_file_mtime_ms($0) }
        return v < 0 ? nil : v
    }
}
