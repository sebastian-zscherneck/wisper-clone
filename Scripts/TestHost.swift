import Darwin
import Testing

// Minimal Swift Testing runner for Command Line Tools-only machines.
// `swift test` silently runs zero tests without a full Xcode install because
// SwiftPM's testing helper fails to load Testing.framework (missing
// lib_TestingInterop.dylib rpath). This host dlopens the built test bundle and
// invokes the Swift Testing entry point directly. Used by Scripts/run-tests.sh.
@main
struct TestHost {
    static func main() async {
        guard CommandLine.arguments.count > 1 else {
            print("usage: testhost <path-to-test-bundle-binary>")
            exit(64)
        }
        let bundlePath = CommandLine.arguments[1]
        guard dlopen(bundlePath, RTLD_NOW) != nil else {
            print("dlopen failed: \(String(cString: dlerror()))")
            exit(70)
        }
        exit(await Testing.__swiftPMEntryPoint(passing: nil) as Int32)
    }
}
