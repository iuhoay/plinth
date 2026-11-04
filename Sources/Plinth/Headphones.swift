import CoreAudio

/// Whether the knock is going to headphones, where it can be rendered for the
/// ears. Bluetooth outputs count, as most of them are earbuds and headphones;
/// so does the built-in output while something is plugged into its jack.
/// Speakers get a plain pan: rendered for ears, they throw the knock to one side.
enum Headphones {
    static func inUse() -> Bool {
        var device = AudioObjectID(0)
        guard get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &device),
              device != 0 else { return false }
        var transport: UInt32 = 0
        _ = get(device, kAudioDevicePropertyTransportType, &transport)
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return true
        case kAudioDeviceTransportTypeBuiltIn:
            var source: UInt32 = 0
            let headphoneJack: UInt32 = 0x6864_706E // 'hdpn'
            return get(device, kAudioDevicePropertyDataSource, &source, scope: kAudioObjectPropertyScopeOutput)
                && source == headphoneJack
        default:
            return false
        }
    }

    /// Every property read here, device IDs included, is a UInt32.
    private static func get(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout UInt32,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
