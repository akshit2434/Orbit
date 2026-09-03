import XCTest
@testable import Orbit

final class EnvTests: XCTestCase {
    func testParsesEnvFile() {
        let parsed = EnvLoader.loadEnvString("A=1\n# comment\nB=hello world\nEMPTY=\n")
        XCTAssertEqual(parsed["A"], "1")
        XCTAssertEqual(parsed["B"], "hello world")
        XCTAssertEqual(parsed["EMPTY"], "")
    }
    func testProcessEnvOverridesFile() {
        let cfg = EnvLoader.config(processEnv: ["OPENROUTER_MODEL": "x/y"], fileEnv: ["OPENROUTER_MODEL": "a/b", "OPENROUTER_API_KEY": "k"])
        XCTAssertEqual(cfg.openRouterModel, "x/y")
        XCTAssertEqual(cfg.openRouterKey, "k")
    }
}
