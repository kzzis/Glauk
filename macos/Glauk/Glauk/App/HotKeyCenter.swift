import AppKit
import Carbon.HIToolbox

/// C のコールバックは値を持ち回れないので、ここに置いて拾わせる。
private nonisolated(unsafe) var hotKeyTrigger: (() -> Void)?

/// RegisterEventHotKey はアクセシビリティ権限なしでグローバルキーを消費できる。
@MainActor
final class HotKeyCenter {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// 4文字コード "GLK1"。他アプリのホットキーと取り違えないための目印。
    private static let signature: OSType = 0x474C4B31

    var onTrigger: (() -> Void)?

    /// 既定は ⌥Space
    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_Space),
                  modifiers: UInt32 = UInt32(optionKey)) -> Bool {
        unregister()
        hotKeyTrigger = { [weak self] in self?.onTrigger?() }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x474C4B31 else { return noErr }
            DispatchQueue.main.async { hotKeyTrigger?() }
            return noErr
        }, 1, &spec, nil, &handler)
        guard installed == noErr else { return false }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        // 登録解除時に使う参照を保持する。
        let status = RegisterEventHotKey(keyCode, modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            // 他アプリが同じ組み合わせを押さえていると失敗する
            print("[glauk] ホットキーを登録できませんでした (status=\(status))")
            return false
        }
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        hotKeyTrigger = nil
    }
}
