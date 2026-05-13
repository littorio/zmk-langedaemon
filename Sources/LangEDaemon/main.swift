import Foundation
import Carbon.HIToolbox
import CoreGraphics

struct Config {
    let leftSourceID: String
    let rightSourceID: String
    let passThrough: Bool

    static let defaultLeft = "org.sil.ukelele.keyboardlayout.jinnyswe.jinnyswe"
    static let defaultRight = "org.sil.ukelele.keyboardlayout.unsavedukeleledocument.jinnyrus"
}

enum CLI {
    static func parse(_ args: [String]) -> (mode: String, config: Config) {
        var left = Config.defaultLeft
        var right = Config.defaultRight
        var passThrough = false

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--list-sources":
                return ("list", Config(leftSourceID: left, rightSourceID: right, passThrough: passThrough))
            case "--left-source":
                i += 1
                guard i < args.count else { fatalError("Missing value for --left-source") }
                left = args[i]
            case "--right-source":
                i += 1
                guard i < args.count else { fatalError("Missing value for --right-source") }
                right = args[i]
            case "--pass-through":
                passThrough = true
            case "--help", "-h":
                printUsageAndExit(code: 0)
            default:
                fputs("Unknown argument: \(args[i])\n", stderr)
                printUsageAndExit(code: 2)
            }
            i += 1
        }

        return ("run", Config(leftSourceID: left, rightSourceID: right, passThrough: passThrough))
    }

    static func printUsageAndExit(code: Int32) -> Never {
        let msg = """
        Usage:
          langedaemon [--left-source SOURCE_ID] [--right-source SOURCE_ID] [--pass-through]
          langedaemon --list-sources

        Defaults:
          --left-source  \(Config.defaultLeft)
          --right-source \(Config.defaultRight)

        Notes:
          F20 switches to left source.
          F19 switches to right source.
          By default handled key presses are suppressed.
        """
        print(msg)
        exit(code)
    }
}

final class InputSourceSwitcher {
    func listSources() {
        guard let unmanaged = TISCreateInputSourceList(nil, false) else {
            print("Failed to read input source list")
            return
        }

        let sources = unmanaged.takeRetainedValue() as NSArray
        print("Available input sources:\n")

        for item in sources {
            let src = item as! TISInputSource
            let id = propertyString(src, key: kTISPropertyInputSourceID) ?? "<nil-id>"
            let name = propertyString(src, key: kTISPropertyLocalizedName) ?? "<nil-name>"
            let category = propertyString(src, key: kTISPropertyInputSourceCategory) ?? "<nil-category>"
            let selectable = propertyBool(src, key: kTISPropertyInputSourceIsSelectCapable)
            print("- \(name)\n  id=\(id)\n  category=\(category)\n  selectable=\(selectable)\n")
        }
    }

    func selectSource(id: String) -> Bool {
        let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let unmanaged = TISCreateInputSourceList(properties, false) else {
            fputs("Cannot query input source '\(id)'\n", stderr)
            return false
        }

        let sources = unmanaged.takeRetainedValue() as NSArray
        guard sources.count > 0 else {
            fputs("Input source not found: '\(id)'\n", stderr)
            return false
        }
        let source = sources.firstObject as! TISInputSource

        let status = TISSelectInputSource(source)
        if status != noErr {
            fputs("TISSelectInputSource failed for '\(id)' with status \(status)\n", stderr)
            return false
        }

        return true
    }

    private func propertyString(_ src: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(src, key) else { return nil }
        let cfType = unsafeBitCast(raw, to: CFTypeRef.self)
        if CFGetTypeID(cfType) == CFStringGetTypeID() {
            return (cfType as! CFString) as String
        }
        return nil
    }

    private func propertyBool(_ src: TISInputSource, key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(src, key) else { return false }
        let cfType = unsafeBitCast(raw, to: CFTypeRef.self)
        if CFGetTypeID(cfType) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((cfType as! CFBoolean))
        }
        return false
    }
}

final class Daemon {
    private let config: Config
    private let switcher = InputSourceSwitcher()

    init(config: Config) {
        self.config = config
    }

    func run() {
        print("Starting langedaemon")
        print("F20 -> \(config.leftSourceID)")
        print("F19 -> \(config.rightSourceID)")
        print(config.passThrough ? "Handled keys are passed through" : "Handled keys are suppressed")

        let mask = (1 << CGEventType.keyDown.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            fputs("Failed to create event tap. Grant Accessibility + Input Monitoring, then retry.\n", stderr)
            exit(1)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    fileprivate func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch keyCode {
        case UInt16(kVK_F20):
            _ = switcher.selectSource(id: config.leftSourceID)
            return config.passThrough ? Unmanaged.passRetained(event) : nil
        case UInt16(kVK_F19):
            _ = switcher.selectSource(id: config.rightSourceID)
            return config.passThrough ? Unmanaged.passRetained(event) : nil
        default:
            return Unmanaged.passRetained(event)
        }
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard type == .keyDown, let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let daemon = Unmanaged<Daemon>.fromOpaque(userInfo).takeUnretainedValue()
    return daemon.handle(event)
}

let parsed = CLI.parse(CommandLine.arguments)
switch parsed.mode {
case "list":
    InputSourceSwitcher().listSources()
default:
    Daemon(config: parsed.config).run()
}
