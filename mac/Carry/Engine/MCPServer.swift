import Foundation
import Network

/// Streamable HTTP MCP on `http://127.0.0.1:47850/mcp` while the app runs: JSON-RPC 2.0 over `POST /mcp`,
/// answered with `application/json`. Loopback only; any `Origin` that is not localhost is refused.
/// Tools and results are those of cli/src/carry/mcp_server.py (`digest`, `search`, `recent`, `item`, `sources`;
/// resource `carry://digest/today`).
final class MCPServer {
    static let shared = MCPServer()
    static let port: UInt16 = 47850
    static let url = "http://127.0.0.1:47850/mcp"
    static let instructions =
        "Carry exposes the owner's phone context: photos and screenshots (with OCR text when Pro is on), voice memos "
        + "(with transcripts), notes, messages, calendar, reminders, Safari, screen time, plus health, places and a share inbox "
        + "captured by the Carry iPhone app. Start with digest('today') for an overview; use search for anything specific."

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.carry.mcp")
    private(set) var isRunning = false
    private(set) var lastError: String?
    private let sessionID = UUID().uuidString.lowercased()

    private init() {}

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.lastError = nil
                    AppLog.write("mcp listening on \(Self.url)")
                case .failed(let error):
                    self.isRunning = false
                    self.lastError = error.localizedDescription
                    AppLog.write("mcp failed: \(error.localizedDescription)")
                    self.listener = nil
                case .cancelled:
                    self.isRunning = false
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            lastError = error.localizedDescription
            AppLog.write("mcp could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - HTTP/1.1, the minimum

    private struct Request {
        var method = ""
        var path = ""
        var headers: [String: String] = [:]
        var body = Data()
    }

    private final class ConnectionState {
        var buffer = Data()
    }

    private func handle(_ connection: NWConnection) {
        if case .hostPort(let host, _) = connection.endpoint, !Self.isLoopback(host) {
            connection.cancel()
            return
        }
        let state = ConnectionState()
        connection.start(queue: queue)
        receive(connection, state)
    }

    private static func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback || a.isIPv4Mapped && a.asIPv4?.isLoopback == true
        case .name(let n, _): return n == "localhost" || n == "127.0.0.1" || n == "::1"
        @unknown default: return false
        }
    }

    private func receive(_ connection: NWConnection, _ state: ConnectionState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { state.buffer.append(data) }
            while let (request, consumed) = self.parse(state.buffer) {
                state.buffer.removeFirst(consumed)
                let (response, close) = self.respond(to: request)
                connection.send(content: response, completion: .contentProcessed { _ in
                    if close { connection.cancel() }
                })
                if close { return }
            }
            if state.buffer.count > 4 << 20 { connection.cancel(); return }
            if complete || error != nil { connection.cancel(); return }
            self.receive(connection, state)
        }
    }

    /// One complete request from the front of the buffer, or nil while it is still incomplete.
    private func parse(_ buffer: Data) -> (Request, Int)? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: buffer[buffer.startIndex ..< headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        var request = Request()
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return (request, buffer.count) }
        request.method = String(requestLine[0]).uppercased()
        request.path = String(requestLine[1])
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            request.headers[name] = value
        }
        let length = Int(request.headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.endIndex - bodyStart >= length else { return nil }
        request.body = Data(buffer[bodyStart ..< bodyStart + length])
        return (request, (bodyStart - buffer.startIndex) + length)
    }

    private func response(_ status: Int, _ reason: String, body: Data = Data(), contentType: String = "application/json",
                          extra: [String: String] = [:], close: Bool = false) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Mcp-Session-Id: \(sessionID)\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += close ? "Connection: close\r\n" : "Connection: keep-alive\r\n"
        head += "\r\n"
        return Data(head.utf8) + body
    }

    private func respond(to request: Request) -> (Data, Bool) {
        let close = request.headers["connection"]?.lowercased() == "close"
        if let origin = request.headers["origin"], !origin.isEmpty, !Self.originAllowed(origin) {
            return (response(403, "Forbidden", body: Data("{\"error\":\"origin not allowed\"}".utf8), close: true), true)
        }
        guard request.path == "/mcp" || request.path.hasPrefix("/mcp?") else {
            return (response(404, "Not Found", body: Data("{\"error\":\"not found\"}".utf8), close: close), close)
        }
        switch request.method {
        case "POST":
            guard let payload = JSON.parse(request.body) else {
                let err = Self.errorResponse(id: .null, code: -32700, message: "Parse error")
                return (response(400, "Bad Request", body: Data(err.dumps().utf8), close: close), close)
            }
            if case .array(let batch) = payload {
                let answers = batch.compactMap { Self.handle($0) }
                if answers.isEmpty { return (response(202, "Accepted", close: close), close) }
                return (response(200, "OK", body: Data(JSON.array(answers).dumps().utf8), close: close), close)
            }
            guard let answer = Self.handle(payload) else {
                return (response(202, "Accepted", close: close), close)
            }
            return (response(200, "OK", body: Data(answer.dumps().utf8), close: close), close)
        case "GET":
            return (response(405, "Method Not Allowed", body: Data("{\"error\":\"no server-sent events; POST JSON-RPC\"}".utf8),
                             extra: ["Allow": "POST, DELETE"], close: close), close)
        case "DELETE":
            return (response(200, "OK", body: Data("{}".utf8), close: close), close)
        case "OPTIONS":
            return (response(204, "No Content", extra: ["Allow": "POST, DELETE"], close: close), close)
        default:
            return (response(405, "Method Not Allowed", extra: ["Allow": "POST, DELETE"], close: close), close)
        }
    }

    private static func originAllowed(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    // MARK: - JSON-RPC

    private static func errorResponse(id: JSON, code: Int, message: String, data: JSON? = nil) -> JSON {
        var err: [(String, JSON)] = [("code", .num(code)), ("message", .string(message))]
        if let data { err.append(("data", data)) }
        return .object([("jsonrpc", .string("2.0")), ("id", id), ("error", .object(err))])
    }

    private static func result(id: JSON, _ value: JSON) -> JSON {
        .object([("jsonrpc", .string("2.0")), ("id", id), ("result", value)])
    }

    /// One JSON-RPC message → its response, or nil for a notification.
    static func handle(_ message: JSON) -> JSON? {
        let id = message["id"]
        guard let method = message["method"]?.string else {
            return id.map { errorResponse(id: $0, code: -32600, message: "Invalid Request") }
        }
        let params = message["params"] ?? .object([])
        guard let id else {
            // Notifications: notifications/initialized, notifications/cancelled, …
            return nil
        }
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.string ?? "2025-06-18"
            return result(id: id, .object([
                ("protocolVersion", .string(requested)),
                ("capabilities", .object([
                    ("experimental", .object([])),
                    ("prompts", .object([("listChanged", .bool(false))])),
                    ("resources", .object([("subscribe", .bool(false)), ("listChanged", .bool(false))])),
                    ("tools", .object([("listChanged", .bool(false))])),
                ])),
                ("serverInfo", .object([("name", .string("carry")), ("version", .string(Engine.version))])),
                ("instructions", .string(instructions)),
            ]))
        case "ping":
            return result(id: id, .object([]))
        case "tools/list":
            return result(id: id, .object([("tools", .array(Tools.list))]))
        case "tools/call":
            let name = params["name"]?.string ?? ""
            let args = params["arguments"] ?? .object([])
            return result(id: id, Tools.call(name, args))
        case "resources/list":
            return result(id: id, .object([("resources", .array([
                .object([("uri", .string("carry://digest/today")), ("name", .string("today_resource")),
                         ("description", .string("")), ("mimeType", .string("text/plain"))]),
            ]))]))
        case "resources/templates/list":
            return result(id: id, .object([("resourceTemplates", .array([]))]))
        case "resources/read":
            let uri = params["uri"]?.string ?? ""
            guard uri == "carry://digest/today" else {
                return errorResponse(id: id, code: -32002, message: "Resource not found", data: .string(uri))
            }
            return result(id: id, .object([("contents", .array([
                .object([("uri", .string(uri)), ("mimeType", .string("text/plain")), ("text", .string(Tools.digest("today")))]),
            ]))]))
        case "prompts/list":
            return result(id: id, .object([("prompts", .array([]))]))
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found", data: .string(method))
        }
    }

    // MARK: - Tools (mcp_server.py)

    enum Tools {
        static let list: [JSON] = [
            tool("digest", "The daily Markdown digest. `date` is YYYY-MM-DD, 'today' or 'yesterday'.",
                 properties: [("date", .object([("default", .string("today")), ("title", .string("Date")), ("type", .string("string"))]))],
                 required: [], output: .object([("title", .string("Result")), ("type", .string("string"))])),
            tool("search", "Full-text search across everything (trigram, so Chinese works). `source` filters to one source name;\n`since` is an ISO date.",
                 properties: [
                     ("query", .object([("title", .string("Query")), ("type", .string("string"))])),
                     ("source", nullable("Source")), ("since", nullable("Since")),
                     ("limit", .object([("default", .num(20)), ("title", .string("Limit")), ("type", .string("integer"))])),
                 ], required: ["query"], output: listOfObjects),
            tool("recent", "Most recent items from one source: photos, screenshots, voice_memos, notes, messages, calendar, reminders,\nsafari, screen_time, health, location, inbox.",
                 properties: [
                     ("source", .object([("title", .string("Source")), ("type", .string("string"))])),
                     ("limit", .object([("default", .num(20)), ("title", .string("Limit")), ("type", .string("integer"))])),
                 ], required: ["source"], output: listOfObjects),
            tool("item", "One item in full (for long transcripts or OCR text).",
                 properties: [("id", .object([("title", .string("Id")), ("type", .string("string"))]))], required: ["id"],
                 output: .object([("anyOf", .array([.object([("additionalProperties", .bool(true)), ("type", .string("object"))]), .object([("type", .string("null"))])])),
                                  ("title", .string("Result"))])),
            tool("sources", "Which sources are switched on, and who decided (phone or mac).", properties: [], required: [], output: listOfObjects),
        ]

        private static var listOfObjects: JSON {
            .object([("items", .object([("additionalProperties", .bool(true)), ("type", .string("object"))])),
                     ("title", .string("Result")), ("type", .string("array"))])
        }

        private static func nullable(_ title: String) -> JSON {
            .object([("anyOf", .array([.object([("type", .string("string"))]), .object([("type", .string("null"))])])),
                     ("default", .null), ("title", .string(title))])
        }

        private static func tool(_ name: String, _ description: String, properties: [(String, JSON)], required: [String], output: JSON) -> JSON {
            var input: [(String, JSON)] = [("properties", .object(properties))]
            if !required.isEmpty { input.append(("required", .array(required.map { .string($0) }))) }
            input.append(("type", .string("object")))
            input.append(("title", .string("\(name)Arguments")))
            return .object([
                ("description", .string(description)),
                ("inputSchema", .object(input)),
                ("name", .string(name)),
                ("outputSchema", .object([("properties", .object([("result", output)])), ("required", .array([.string("result")])),
                                          ("type", .string("object")), ("title", .string("\(name)Output"))])),
            ])
        }

        /// A tool result the way FastMCP renders it: one text block per list item (or one for a scalar), plus
        /// `structuredContent: {"result": …}`.
        private static func done(_ value: JSON) -> JSON {
            var content: [JSON] = []
            switch value {
            case .array(let items):
                content = items.map { .object([("text", .string($0.dumps(indent: 2))), ("type", .string("text"))]) }
            case .null:
                content = []
            case .string(let s):
                content = [.object([("text", .string(s)), ("type", .string("text"))])]
            default:
                content = [.object([("text", .string(value.dumps(indent: 2))), ("type", .string("text"))])]
            }
            return .object([("content", .array(content)), ("isError", .bool(false)), ("structuredContent", .object([("result", value)]))])
        }

        private static func failed(_ message: String) -> JSON {
            .object([("content", .array([.object([("text", .string(message)), ("type", .string("text"))])])), ("isError", .bool(true))])
        }

        static func call(_ name: String, _ args: JSON) -> JSON {
            do {
                switch name {
                case "digest":
                    return done(.string(digest(args["date"]?.string ?? "today")))
                case "search":
                    guard let query = args["query"]?.string else { return failed("Error executing tool search: query is required") }
                    let store = try Store()
                    defer { store.close() }
                    let rows = try store.search(query, source: args["source"]?.string, since: args["since"]?.string,
                                                limit: Int(args["limit"]?.int ?? 20))
                    return done(.array(rows.map(\.mcpJSON)))
                case "recent":
                    guard let source = args["source"]?.string else { return failed("Error executing tool recent: source is required") }
                    let store = try Store()
                    defer { store.close() }
                    return done(.array(try store.recent(source, limit: Int(args["limit"]?.int ?? 20)).map(\.mcpJSON)))
                case "item":
                    guard let id = args["id"]?.string else { return failed("Error executing tool item: id is required") }
                    let store = try Store()
                    defer { store.close() }
                    return done(try store.get(id).map(\.mcpJSON) ?? .null)
                case "sources":
                    let (enabled, by) = Config.effectiveSources(Config.load())
                    return done(.array(Sources.all.map { s in
                        .object([("name", .string(s.name)), ("label", .string(s.label)), ("channel", .string(s.channel.rawValue)),
                                 ("enabled", .bool(enabled[s.name] ?? s.defaultOn)), ("decided_by", .string(by)), ("reads", .string(s.reads))])
                    }))
                default:
                    return failed("Unknown tool: \(name)")
                }
            } catch {
                return failed("Error executing tool \(name): \(error)")
            }
        }

        /// The daily Markdown digest. `date` is YYYY-MM-DD, 'today' or 'yesterday'.
        static func digest(_ dateArg: String) -> String {
            var date = dateArg
            if date == "today" {
                date = PyTime.day(of: PyTime.now())
            } else if date == "yesterday" {
                date = PyTime.day(of: PyTime.now().addingTimeInterval(-86_400))
            }
            let p = CarryPaths.context.appendingPathComponent("\(date).md")
            if let text = try? String(contentsOf: p, encoding: .utf8) { return text }
            return "No digest for \(date). Run `carry sync` on the Mac."
        }
    }
}
