import Foundation
import Testing
@testable import DontSleepKit

struct ControlSocketTests {
    /// A socket path of its own for each test, short enough for a socket address.
    private func temporaryPath() -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ds-\(UUID().uuidString.prefix(8))")
        return folder.appending(path: "control.sock").path
    }

    private func remove(_ path: String) {
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func requestAndAnswerCrossTheSocket() throws {
        let path = temporaryPath()
        defer { remove(path) }
        let server = ControlServer(path: path) { request in
            Response(status: Status(
                running: true, active: request.action == .on,
                until: request.duration.map { Date(timeIntervalSince1970: $0) },
                displaySleepAllowed: request.allowDisplaySleep ?? false, version: "9.9"))
        }
        try server.start()
        defer { server.stop() }

        let on = try ControlClient.send(Request(.on, duration: 1_800_000_000, allowDisplaySleep: true), to: path)
        #expect(on.error == nil)
        #expect(on.status?.active == true)
        #expect(on.status?.displaySleepAllowed == true)
        #expect(on.status?.until == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(on.status?.version == "9.9")

        // The listener keeps serving after the first command.
        for _ in 0..<20 {
            #expect(try ControlClient.send(Request(.status), to: path).status?.active == false)
        }
    }

    @Test func socketIsPrivateToTheUser() throws {
        let path = temporaryPath()
        defer { remove(path) }
        let server = ControlServer(path: path) { _ in Response() }
        try server.start()
        defer { server.stop() }

        let folder = (path as NSString).deletingLastPathComponent
        let folderMode = try #require(FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? NSNumber)
        let socketMode = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
        #expect(folderMode.intValue == 0o700)
        #expect(socketMode.intValue == 0o600)
    }

    @Test func nothingListening() {
        let path = temporaryPath()
        #expect(throws: ControlClient.Failure.notRunning) {
            try ControlClient.send(Request(.status), to: path)
        }
    }

    @Test func socketLeftBehindCountsAsNotRunning() throws {
        let path = temporaryPath()
        defer { remove(path) }
        let server = ControlServer(path: path) { _ in Response() }
        try server.start()
        server.stop()
        #expect(throws: ControlClient.Failure.notRunning) {
            try ControlClient.send(Request(.status), to: path)
        }

        // What a killed app leaves behind: a socket file nobody listens on.
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        let address = try #require(ControlSocket.address(path))
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        #expect(ControlSocket.withSocketAddress(address) { bind(descriptor, $0, $1) } == 0)
        close(descriptor)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(throws: ControlClient.Failure.notRunning) {
            try ControlClient.send(Request(.status), to: path)
        }

        // The next start takes the path over.
        let next = ControlServer(path: path) { _ in Response(status: Status(running: true, active: true, displaySleepAllowed: false)) }
        try next.start()
        defer { next.stop() }
        #expect(try ControlClient.send(Request(.status), to: path).status?.active == true)
    }

    @Test func garbageGetsAnErrorAndTheListenerSurvives() throws {
        let path = temporaryPath()
        defer { remove(path) }
        let server = ControlServer(path: path) { _ in Response(status: Status(running: true, active: false, displaySleepAllowed: false)) }
        try server.start()
        defer { server.stop() }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(descriptor) }
        let address = try #require(ControlSocket.address(path))
        #expect(ControlSocket.withSocketAddress(address) { connect(descriptor, $0, $1) } == 0)
        #expect(ControlSocket.write(Data("not json\n".utf8), to: descriptor))
        let line = try #require(ControlSocket.readLine(from: descriptor))
        let response = try ControlCoding.decode(Response.self, from: line)
        #expect(response.error != nil)
        #expect(response.status == nil)

        #expect(try ControlClient.send(Request(.status), to: path).status?.running == true)
    }

    @Test func pathsTooLongForASocketAreRefused() {
        let path = "/tmp/" + String(repeating: "x", count: 120) + "/control.sock"
        #expect(ControlSocket.address(path) == nil)
        #expect(throws: (any Error).self) {
            try ControlClient.send(Request(.status), to: path)
        }
        #expect(ControlSocket.path.utf8.count < ControlSocket.maximumPathLength)
        #expect(ControlSocket.path.hasSuffix("/control.sock"))
    }
}
