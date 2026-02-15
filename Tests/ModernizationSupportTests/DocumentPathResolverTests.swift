import XCTest
@testable import ModernizationSupport

final class DocumentPathResolverTests: XCTestCase {
    func testUserDocumentRootFromSimulatorPath() {
        let path = "/Users/test/Library/Developer/CoreSimulator/Devices/abc/data/Containers/Data/Application/xyz/Documents"
        XCTAssertEqual(
            DocumentPathResolver.userDocumentRoot(from: path),
            "/Users/test/Library/Documents"
        )
    }

    func testUserDocumentRootWithInvalidPathReturnsNil() {
        XCTAssertNil(DocumentPathResolver.userDocumentRoot(from: "/tmp"))
    }

    func testAppScopedDocumentAliasRootUsesDefaultAppName() {
        let path = "/Users/test/Library/Developer/CoreSimulator/Devices/abc/data"
        XCTAssertEqual(
            DocumentPathResolver.appScopedDocumentAliasRoot(from: path),
            "/Users/test/Library/Documents/ffmpeg_tutorial"
        )
    }

    func testNeedsSymlinkRefreshWhenTargetsDiffer() {
        XCTAssertTrue(DocumentPathResolver.needsSymlinkRefresh(currentLinkTarget: "/old", expectedTarget: "/new"))
        XCTAssertFalse(DocumentPathResolver.needsSymlinkRefresh(currentLinkTarget: "/same", expectedTarget: "/same"))
    }
}
