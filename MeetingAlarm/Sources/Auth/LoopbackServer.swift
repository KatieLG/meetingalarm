import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that captures the OAuth redirect.
final class LoopbackServer {
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<URLComponents, Error>?
    private var pendingCallback: Result<URLComponents, Error>?

    /// Starts listening on a random free port and returns it.
    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.handle(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerStateChanged(state) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.start(queue: .main)
        }
    }

    /// Waits for the browser to hit the redirect URI. Returns its query.
    func waitForCallback() async throws -> URLComponents {
        if let pending = pendingCallback {
            pendingCallback = nil
            return try pending.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    func stop(with error: Error = CancellationError()) {
        listener?.cancel()
        listener = nil
        finish(.failure(error))
        if let ready = readyContinuation {
            readyContinuation = nil
            ready.resume(throwing: error)
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        guard let ready = readyContinuation else { return }
        switch state {
        case .ready:
            readyContinuation = nil
            ready.resume(returning: listener?.port?.rawValue ?? 0)
        case .failed(let error):
            readyContinuation = nil
            ready.resume(throwing: error)
        case .cancelled:
            readyContinuation = nil
            ready.resume(throwing: CancellationError())
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                self?.respond(to: data, on: connection)
            }
        }
    }

    private func respond(to data: Data?, on connection: NWConnection) {
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        // Request line: "GET /?code=...&state=... HTTP/1.1"
        let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first
        let components = target.flatMap { URLComponents(string: "http://127.0.0.1\($0)") }
        let items = components?.queryItems ?? []
        let isCallback = items.contains { $0.name == "code" || $0.name == "error" }

        let body: String
        let status: String
        if isCallback {
            status = "200 OK"
            let failed = items.contains { $0.name == "error" }
            body = Self.page(
                title: failed ? "Sign-in cancelled" : "Signed in to MeetingAlarm",
                message: failed ? "You can close this tab and try again." : "You can close this tab and return to MeetingAlarm."
            )
        } else {
            status = "404 Not Found"
            body = ""
        }
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        if isCallback, let components {
            finish(.success(components))
            listener?.cancel()
            listener = nil
        }
    }

    private func finish(_ result: Result<URLComponents, Error>) {
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else if pendingCallback == nil, case .success = result {
            pendingCallback = result
        }
    }

    private static func page(title: String, message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font-family:-apple-system,system-ui;display:flex;align-items:center;justify-content:center;height:90vh;color:#222}
        div{text-align:center}h1{font-weight:600}</style></head>
        <body><div><h1>\(title)</h1><p>\(message)</p></div></body></html>
        """
    }
}
