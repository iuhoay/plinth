import CoreAudio
import Foundation

/// Whether another app is listening to a microphone, as in a call or meeting.
///
/// It asks Core Audio which processes are reading input. A device's own
/// "running somewhere" flag won't do: it is also set while a headset or other
/// device that both plays and records is only playing, such as during a knock.
/// Reading the process list opens no device, so it needs no microphone permission.
enum Microphone {
    /// Core Audio lists processes from macOS 14.2.
    static var canTell: Bool {
        if #available(macOS 14.2, *) { true } else { false }
    }

    static func inUseByOthers() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let me = getpid()
        return objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).contains {
            value($0, kAudioProcessPropertyIsRunningInput) == 1 && pid_t(value($0, kAudioProcessPropertyPID)) != me
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func value(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : 0
    }
}
