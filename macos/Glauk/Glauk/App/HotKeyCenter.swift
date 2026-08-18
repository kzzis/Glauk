// HotKeyCenter.swift
import AppKit
import Carbon.HIToolbox

/// C のコールバックは値を持ち回れないので、ここに置いて拾わせる。
private nonisolated(unsafe) var hotKeyTrigger: (() -> Void)?

/// アプリが非アクティブでもキーを拾う。
///
/// ★ この用途で使える方法は限られる:
///   - NSEvent.addGlobalMonitorForEvents … キーを消費できず、他アプリにも届く
///   - CGEventTap … アクセシビリティ権限が要る。要求が重い
///   - Carbon の RegisterEventHotKey … 権限不要でキーを消費できる ← これ
///   古いAPIだが代替が無く、Alfred や Raycast も同じ方式。
///
/// soffes/HotKey という薄いラッパーもあるが、この程度のために依存を増やさず直接叩く。
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
        // ★ ref をプロパティに持ち続ける。ローカル変数にすると関数を抜けた時点で
        //   登録が解除され、「登録したのに反応しない」になる。
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
