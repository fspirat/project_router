import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import RouterCore

/// A valid-format dummy token (not a real one).
let dummyToken = "fsr1_" + String(repeating: "A", count: 43)
let testBase = URL(string: "https://example.test/router/app/v1/")!

/// Records requests and replies from a queue.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case http(status: Int, body: String, headers: [String: String])
        case failure(Error)
    }

    private let lock = NSLock()
    private var queue: [Reply] = []
    private var recorded: [URLRequest] = []
    /// Used when the queue is empty.
    private var fallback: Reply = .failure(URLError(.notConnectedToInternet))

    func enqueue(_ status: Int, _ body: String, headers: [String: String] = [:]) {
        lock.lock()
        queue.append(.http(status: status, body: body, headers: headers))
        lock.unlock()
    }

    func enqueueFailure(_ error: Error) {
        lock.lock()
        queue.append(.failure(error))
        lock.unlock()
    }

    func setFallback(_ reply: Reply) {
        lock.lock()
        fallback = reply
        lock.unlock()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func next(for request: URLRequest) -> Reply {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        if queue.isEmpty {
            return fallback
        }
        return queue.removeFirst()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = next(for: request)
        switch reply {
        case .failure(let error):
            throw error
        case .http(let status, let body, let headers):
            let url = request.url ?? testBase
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                throw URLError(.badServerResponse)
            }
            return (Data(body.utf8), response)
        }
    }
}

/// Instant clock: `sleep` only advances the time.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval
    private var slept: [TimeInterval] = []

    init(start: TimeInterval) {
        current = start
    }

    func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current += seconds
        slept.append(seconds)
        lock.unlock()
    }

    var sleeps: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return slept
    }

    var runtime: RuntimeClock {
        return RuntimeClock(
            now: { [self] in self.now() },
            sleep: { [self] seconds in self.advance(seconds) }
        )
    }
}

func makeClient(_ transport: MockTransport, clock: FakeClock = FakeClock(start: TimeInterval(SampleJSON.now)), token: String? = dummyToken) -> APIClient {
    let box = TokenBox(token)
    return APIClient(baseURL: testBase, transport: transport, clock: clock.runtime, tokenProvider: { box.token })
}

func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    return try JSONDecoder().decode(T.self, from: Data(text.utf8))
}

/// The body of a recorded request parsed as JSON.
func bodyJSON(_ request: URLRequest) -> JSONValue? {
    guard let data = request.httpBody else {
        return nil
    }
    return try? JSONValue.parse(data)
}

let nowT = TimeInterval(SampleJSON.now)
