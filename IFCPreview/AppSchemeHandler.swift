import Foundation
import WebKit
import os

/// Serves the bundled `Web/` folder and the previewed IFC file over a custom
/// `ifcql://app/...` scheme. `fetch()` inside WebKit does not work for `file://`
/// URLs, and WASM must be fetched, so a scheme handler is the only clean path.
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "ifcql"
    static let host = "app"

    private static let log = Logger(subsystem: "com.ibaranov.IFCQuickLook", category: "scheme")

    /// The IFC file being previewed, and the token identifying the load that may read it.
    /// Requests carrying a stale token are refused so a page left over from a previous
    /// preview can never be handed the current file's bytes.
    var fileURL: URL?
    var modelToken = ""

    private let webRoot: URL = {
        Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true).standardizedFileURL
    }()

    /// Tasks WebKit has started and not yet stopped. Membership is what says whether this
    /// handler still owes the task a response; entries are added in `start` and removed in
    /// `stop` or once the task has been completed, so an address reused by a later task is
    /// never mistaken for an older one.
    private var liveTasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        liveTasks.insert(ObjectIdentifier(task))
        let url = task.request.url
        let path = (url?.path).flatMap { $0.isEmpty ? nil : $0 } ?? "/"

        do {
            let (data, mime) = try resource(for: path, query: url?.query)
            respond(task, status: 200, mime: mime, data: data)
        } catch let error as ResourceError {
            Self.log.error("\(path, privacy: .public): \(error.status) \(error.message, privacy: .public)")
            respond(task, status: error.status, mime: "text/plain; charset=utf-8", data: Data(error.message.utf8))
        } catch {
            Self.log.error("\(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            respond(task, status: 500, mime: "text/plain; charset=utf-8", data: Data(error.localizedDescription.utf8))
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        liveTasks.remove(ObjectIdentifier(task))
    }

    // MARK: - Resolution

    private struct ResourceError: Error {
        let status: Int
        let message: String
    }

    private func resource(for path: String, query: String?) throws -> (Data, String) {
        if path == "/model.ifc" {
            let token = URLComponents(string: "?" + (query ?? ""))?
                .queryItems?.first(where: { $0.name == "t" })?.value ?? ""
            guard token == modelToken else {
                throw ResourceError(status: 409, message: "Stale preview request")
            }
            guard let fileURL else { throw ResourceError(status: 404, message: "No file to preview") }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            return (data, "application/octet-stream")
        }

        let relative = path == "/" ? "index.html" : String(path.dropFirst())
        let target = webRoot.appendingPathComponent(relative).standardizedFileURL
        guard target.path.hasPrefix(webRoot.path + "/") else {
            throw ResourceError(status: 403, message: "Forbidden")
        }
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw ResourceError(status: 404, message: "Not found: \(relative)")
        }
        let data = try Data(contentsOf: target, options: .mappedIfSafe)
        return (data, Self.mimeType(forExtension: target.pathExtension))
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "wasm": return "application/wasm"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "ifc": return "application/x-step"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Response

    /// Terminates the task exactly once: either with a full response or with an explicit
    /// failure. WebKit applies no timeout of its own, so a task left unfinished would keep
    /// the page waiting on that resource forever.
    private func respond(_ task: WKURLSchemeTask, status: Int, mime: String, data: Data) {
        let id = ObjectIdentifier(task)
        guard liveTasks.contains(id) else { return }
        liveTasks.remove(id)

        let headers = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
        ]
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            Self.log.error("could not build a response; failing the task")
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
