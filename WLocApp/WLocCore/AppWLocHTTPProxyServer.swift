import CFNetwork
import Darwin
import Foundation
import Security

enum AppWLocProxyError: Error, LocalizedError {
    case socketCreateFailed
    case socketBindFailed
    case socketListenFailed
    case unsupportedProxyRequest
    case unsupportedHost(String)
    case tlsIdentityMissing(Error)
    case tlsStreamCreateFailed
    case tlsOpenFailed
    case httpRequestInvalid
    case upstreamFailed

    var errorDescription: String? {
        switch self {
        case .socketCreateFailed:
            return "\(AppWLocConfig.displayName) 本地代理 socket 创建失败"
        case .socketBindFailed:
            return "\(AppWLocConfig.displayName) 本地代理端口绑定失败"
        case .socketListenFailed:
            return "\(AppWLocConfig.displayName) 本地代理监听失败"
        case .unsupportedProxyRequest:
            return "\(AppWLocConfig.displayName) 本地代理只支持 CONNECT 请求"
        case .unsupportedHost(let host):
            return "\(AppWLocConfig.displayName) 本地代理不处理该域名：\(host)"
        case .tlsIdentityMissing(let error):
            return "\(AppWLocConfig.displayName) 本地代理证书不可用：\(error.localizedDescription)"
        case .tlsStreamCreateFailed:
            return "\(AppWLocConfig.displayName) TLS 流创建失败"
        case .tlsOpenFailed:
            return "\(AppWLocConfig.displayName) TLS 握手失败"
        case .httpRequestInvalid:
            return "\(AppWLocConfig.displayName) HTTPS 请求解析失败"
        case .upstreamFailed:
            return "\(AppWLocConfig.displayName) 上游请求失败"
        }
    }
}

/// 扩展内的本地 HTTPS 代理。
///
/// VPN 配置只把定位服务的两个域名导向这个代理。代理收到 CONNECT 后，
/// 使用已配置并被系统信任的证书完成 TLS 握手。命中 `/clls/wloc` 且存在锁定
/// 坐标时，代理会直接基于客户端请求构造一个精简 WLoc 响应；其他路径保持
/// 原样转发，避免影响旧定位流程。
final class AppWLocHTTPProxyServer {

    private let port: UInt16
    private let queue = DispatchQueue(label: "com.wloc8.proxy.accept")
    private let workerQueue = DispatchQueue(label: "com.wloc8.proxy.worker", qos: .utility, attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        guard listenFD < 0 else { return }

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw AppWLocProxyError.socketCreateFailed
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setNonBlocking(fd)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw AppWLocProxyError.socketBindFailed
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            close(fd)
            throw AppWLocProxyError.socketListenFailed
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 本地代理已监听 127.0.0.1:\(port)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
    }

    private func acceptPendingConnections() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 接收连接失败：\(errno)")
                return
            }

            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 本地代理收到客户端连接 fd=\(clientFD)")
            workerQueue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        configureTimeouts(clientFD)

        do {
            let connectRequest = try readProxyHeader(from: clientFD)
            let target = try parseConnectTarget(connectRequest)
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 本地代理 CONNECT \(target.host):\(target.port)")
            guard AppWLocConfig.appWLocHosts.contains(target.host) else {
                throw AppWLocProxyError.unsupportedHost(target.host)
            }

            #if os(macOS)
            let tlsCertificates: [Any]
            do {
                // locationd 的 TLS 校验不会替代理补齐签发链。macOS 必须发送
                // p12 内的完整链，否则客户端会以 MissingIntermediate 在发出 HTTP 请求前断开。
                tlsCertificates = try AppWLocCertificateStore.shared.loadProxyTLSCertificateChain()
            } catch {
                throw AppWLocProxyError.tlsIdentityMissing(error)
            }
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) macOS TLS 服务端证书链 count=\(tlsCertificates.count)"
            )
            #else
            let identity: SecIdentity
            do {
                identity = try AppWLocCertificateStore.shared.loadProxyIdentity()
            } catch {
                throw AppWLocProxyError.tlsIdentityMissing(error)
            }
            // iOS 保持原有行为，只传入 identity，不改变现有证书处理逻辑。
            let tlsCertificates: [Any] = [identity]
            #endif

            try writeAll(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), to: clientFD)
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 本地代理开始 TLS 握手 host=\(target.host)")
            try handleTLSRequest(clientFD: clientFD, host: target.host, tlsCertificates: tlsCertificates)
        } catch {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 代理连接结束：\(error.localizedDescription)")
            close(clientFD)
        }
    }

    private func handleTLSRequest(clientFD: Int32, host: String, tlsCertificates: [Any]) throws {
        var readStreamRef: Unmanaged<CFReadStream>?
        var writeStreamRef: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, clientFD, &readStreamRef, &writeStreamRef)
        guard let cfReadStream = readStreamRef?.takeRetainedValue(),
              let cfWriteStream = writeStreamRef?.takeRetainedValue() else {
            throw AppWLocProxyError.tlsStreamCreateFailed
        }

        let sslSettings = [
            kCFStreamSSLIsServer as String: true,
            kCFStreamSSLCertificates as String: tlsCertificates
        ] as CFDictionary

        let closeSocketKey = CFStreamPropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket)
        let sslSettingsKey = CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings)
        CFReadStreamSetProperty(cfReadStream, closeSocketKey, kCFBooleanTrue)
        CFWriteStreamSetProperty(cfWriteStream, closeSocketKey, kCFBooleanTrue)
        CFReadStreamSetProperty(cfReadStream, sslSettingsKey, sslSettings)
        CFWriteStreamSetProperty(cfWriteStream, sslSettingsKey, sslSettings)

        let inputStream = cfReadStream as InputStream
        let outputStream = cfWriteStream as OutputStream

        guard CFReadStreamOpen(cfReadStream), CFWriteStreamOpen(cfWriteStream) else {
            throw AppWLocProxyError.tlsOpenFailed
        }
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 本地代理 TLS 已打开 host=\(host)")
        defer {
            inputStream.close()
            outputStream.close()
        }

        let request = try readHTTPRequest(from: inputStream, host: host)
        AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 本地代理 HTTPS \(request.method) https://\(request.host)\(request.path)")
        let shouldLogWLoc = isWLocRequest(request)
        #if os(macOS)
        logMacOSRequest(request)
        #else
        if shouldLogWLoc {
            logWLocRequest(request)
        }
        #endif

        if let lockedResponse = buildLockedWLocResponseIfNeeded(request) {
            let response = AppWLocHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: Data()
            )
            #if os(macOS)
            logMacOSResponse(
                title: "返回客户端 Response（按请求构造）",
                response: response,
                body: lockedResponse,
                request: request,
                wasMutated: true
            )
            #else
            if shouldLogWLoc {
                logWLocSyntheticResponse(lockedResponse, request: request)
            }
            #endif
            try writeHTTPResponse(upstream: response, body: lockedResponse, to: outputStream)
            return
        }

        let upstream = try performUpstreamRequest(request)
        #if os(macOS)
        logMacOSResponse(
            title: "上游 Response",
            response: upstream,
            body: upstream.body,
            request: request,
            wasMutated: false
        )
        logMacOSResponse(
            title: "返回客户端 Response（上游透传）",
            response: upstream,
            body: upstream.body,
            request: request,
            wasMutated: false
        )
        #else
        if shouldLogWLoc {
            logWLocUpstreamResponse(upstream, request: request)
        }

        if shouldLogWLoc {
            logWLocFinalResponse(upstream: upstream, body: upstream.body, originalBody: upstream.body, request: request)
        }
        #endif

        try writeHTTPResponse(upstream: upstream, body: upstream.body, to: outputStream)
    }

    private func performUpstreamRequest(_ request: AppWLocHTTPRequest) throws -> AppWLocHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 15

        for (field, value) in request.headers {
            let lowercased = field.lowercased()
            if lowercased == "host" ||
                lowercased == "connection" ||
                lowercased == "proxy-connection" ||
                lowercased == "content-length" ||
                lowercased == "accept-encoding" {
                continue
            }
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.setValue(request.host, forHTTPHeaderField: "Host")
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<AppWLocHTTPResponse, Error>?

        session.dataTask(with: urlRequest) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                #if os(macOS)
                let nsError = error as NSError
                AppWLocUtils.debugLog(
                    [
                        "\(AppWLocConfig.displayName) macOS 上游请求失败",
                        "URL：\(request.method) \(request.url.absoluteString)",
                        "错误：domain=\(nsError.domain)，code=\(nsError.code)，detail=\(nsError.localizedDescription)",
                        "Request Body 大小：\(request.body.count) bytes"
                    ].joined(separator: "\n")
                )
                #endif
                result = .failure(error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                #if os(macOS)
                AppWLocUtils.debugLog(
                    "\(AppWLocConfig.displayName) macOS 上游未返回 HTTP Response，Request Body 大小=\(request.body.count) bytes，Response Body 大小=\(data?.count ?? 0) bytes"
                )
                #endif
                result = .failure(AppWLocProxyError.upstreamFailed)
                return
            }
            result = .success(AppWLocHTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, item in
                    if let key = item.key as? String {
                        partialResult[key] = "\(item.value)"
                    }
                },
                body: data ?? Data()
            ))
        }.resume()

        semaphore.wait()
        session.invalidateAndCancel()
        if let result {
            return try result.get()
        }
        throw AppWLocProxyError.upstreamFailed
    }

    private func buildLockedWLocResponseIfNeeded(_ request: AppWLocHTTPRequest) -> Data? {
        guard isWLocRequest(request),
              let state = AppWLocStateStore.shared.load() else {
            if isWLocRequest(request) {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 命中接口但未改写：锁定坐标不存在")
            }
            return nil
        }

        do {
            let response = try AppWLocMutator.buildResponseBody(fromRequestBody: request.body, using: state)
            if let d = try? JSONEncoder().encode(state), let str = String(data: d, encoding: .utf8) {
                AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 响应已按请求构造：\(request.host)\(request.path)，参数：\(str)")
            }
            return response
        } catch {
            AppWLocUtils.debugLog("\(AppWLocConfig.displayName) 响应构造失败，已回退上游：\(error.localizedDescription)")
            return nil
        }
    }

    private func isWLocRequest(_ request: AppWLocHTTPRequest) -> Bool {
        request.path == AppWLocConfig.wlocPath ||
            request.path.hasPrefix("\(AppWLocConfig.wlocPath)?")
    }

    #if os(macOS)
    private func logMacOSRequest(_ request: AppWLocHTTPRequest) {
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) macOS 收到 Request",
                "URL：\(request.method) https://\(request.host)\(request.path)",
                "请求头：\(formatHeaders(request.headers))",
                "Request Body 大小：\(request.body.count) bytes",
                "Request Body 详情：\(formatMacOSBody(request.body))"
            ].joined(separator: "\n")
        )
    }

    private func logMacOSResponse(
        title: String,
        response: AppWLocHTTPResponse,
        body: Data,
        request: AppWLocHTTPRequest,
        wasMutated: Bool
    ) {
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) macOS \(title)",
                "URL：https://\(request.host)\(request.path)",
                "状态码：\(response.statusCode)",
                "响应头：\(formatHeaders(response.headers))",
                "是否改写：\(wasMutated ? "是" : "否")",
                "Response Body 大小：\(body.count) bytes",
                "Response Body 详情：\(formatMacOSBody(body))"
            ].joined(separator: "\n")
        )
    }

    private func formatMacOSBody(_ data: Data) -> String {
        guard !data.isEmpty else { return "空" }

        // WLoc request/response 是二进制协议。完整 base64 可直接复制做离线解析，
        // 同时保留 hex 前缀，便于快速判断 ARPC/Protobuf 包头是否正确。
        return "hex前缀=\(formatHexPrefix(data))；base64=\(data.base64EncodedString())"
    }
    #endif

    private func logWLocRequest(_ request: AppWLocHTTPRequest) {
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) 命中接口输入",
                "URL：\(request.method) https://\(request.host)\(request.path)",
                "请求头：\(formatHeaders(request.headers))",
                "请求体：\(formatBody(request.body))"
            ].joined(separator: "\n")
        )
    }

    private func logWLocUpstreamResponse(_ response: AppWLocHTTPResponse, request: AppWLocHTTPRequest) {
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) 上游接口输出",
                "URL：https://\(request.host)\(request.path)",
                "状态码：\(response.statusCode)",
                "响应头：\(formatHeaders(response.headers))",
                "响应体：\(formatBody(response.body))"
            ].joined(separator: "\n")
        )
    }

    private func logWLocFinalResponse(
        upstream: AppWLocHTTPResponse,
        body: Data,
        originalBody: Data,
        request: AppWLocHTTPRequest
    ) {
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) 返回客户端输出",
                "URL：https://\(request.host)\(request.path)",
                "状态码：\(upstream.statusCode)",
                "是否改写：\(body == originalBody ? "否" : "是")",
                "响应体：\(formatBody(body))"
            ].joined(separator: "\n")
        )
    }

    private func logWLocSyntheticResponse(_ body: Data, request: AppWLocHTTPRequest) {
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) 返回客户端输出",
                "URL：https://\(request.host)\(request.path)",
                "状态码：200",
                "是否改写：是",
                "响应来源：按请求构造",
                "响应体：\(formatBody(body))"
            ].joined(separator: "\n")
        )
    }

    private func formatHeaders(_ headers: [String: String]) -> String {
        if headers.isEmpty {
            return "无"
        }
        return headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "；")
    }

    private func formatBody(_ data: Data) -> String {
        if data.isEmpty {
            return "0 bytes"
        }

        // WLoc 是二进制协议，日志保留完整 base64，方便后续复制出来做离线还原和对比。
        return "\(data.count) bytes；hex前缀=\(formatHexPrefix(data))；"
    }

    private func formatHexPrefix(_ data: Data) -> String {
        let prefix = data.prefix(64)
        return prefix.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func writeHTTPResponse(upstream: AppWLocHTTPResponse, body: Data, to stream: OutputStream) throws {
        let reason = HTTPURLResponse.localizedString(forStatusCode: upstream.statusCode)
        var header = "HTTP/1.1 \(upstream.statusCode) \(reason)\r\n"

        for (field, value) in upstream.headers {
            let lowercased = field.lowercased()
            if lowercased == "content-length" ||
                lowercased == "transfer-encoding" ||
                lowercased == "connection" ||
                lowercased == "content-encoding" {
                continue
            }
            header += "\(field): \(value)\r\n"
        }
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"

        try writeAll(Data(header.utf8), to: stream)
        try writeAll(body, to: stream)
    }

    private func readHTTPRequest(from stream: InputStream, host: String) throws -> AppWLocHTTPRequest {
        let headerAndMaybeBody = try readStreamHeader(from: stream)
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = headerAndMaybeBody.range(of: delimiter),
              let rawHeader = String(
                data: headerAndMaybeBody.subdata(in: 0..<headerRange.lowerBound),
                encoding: .utf8
              ) else {
            throw AppWLocProxyError.httpRequestInvalid
        }

        let lines = rawHeader.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw AppWLocProxyError.httpRequestInvalid
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw AppWLocProxyError.httpRequestInvalid
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let field = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[field] = value
        }

        let path = requestParts[1]
        let contentLength = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0
        var body = Data()
        let existingBodyStart = headerRange.upperBound
        if headerAndMaybeBody.count > existingBodyStart {
            body.append(headerAndMaybeBody.subdata(in: existingBodyStart..<headerAndMaybeBody.count))
        }
        if body.count < contentLength {
            body.append(try readExact(from: stream, count: contentLength - body.count))
        }

        guard let url = URL(string: "https://\(host)\(path)") else {
            throw AppWLocProxyError.httpRequestInvalid
        }

        return AppWLocHTTPRequest(
            method: requestParts[0],
            host: host,
            path: path,
            url: url,
            headers: headers,
            body: body
        )
    }

    private func readProxyHeader(from fd: Int32) throws -> String {
        let data = try readSocketHeader(from: fd)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppWLocProxyError.unsupportedProxyRequest
        }
        return text
    }

    private func parseConnectTarget(_ request: String) throws -> (host: String, port: Int) {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            throw AppWLocProxyError.unsupportedProxyRequest
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else {
            throw AppWLocProxyError.unsupportedProxyRequest
        }

        let hostParts = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
        let host = hostParts.first?.lowercased() ?? ""
        let port = hostParts.count > 1 ? Int(hostParts[1]) ?? 443 : 443
        return (host, port)
    }

    private func readSocketHeader(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)

        while data.range(of: Data("\r\n\r\n".utf8)) == nil && data.count < 64 * 1024 {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else {
                throw AppWLocProxyError.unsupportedProxyRequest
            }
        }
        return data
    }

    private func readStreamHeader(from stream: InputStream) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)

        while data.range(of: Data("\r\n\r\n".utf8)) == nil && data.count < 256 * 1024 {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else {
                #if os(macOS)
                logMacOSStreamReadFailure(
                    stage: "读取 HTTPS Request Header",
                    stream: stream,
                    readResult: count,
                    receivedData: data
                )
                #endif
                throw AppWLocProxyError.httpRequestInvalid
            }
        }
        #if os(macOS)
        if data.range(of: Data("\r\n\r\n".utf8)) == nil {
            AppWLocUtils.debugLog(
                "\(AppWLocConfig.displayName) macOS Request Header 超出限制，已读取=\(data.count) bytes，hex前缀=\(formatHexPrefix(data))"
            )
        }
        #endif
        return data
    }

    private func readExact(from stream: InputStream, count: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(max(count, 1), 8192))

        while data.count < count {
            let remaining = min(buffer.count, count - data.count)
            let readCount = stream.read(&buffer, maxLength: remaining)
            if readCount > 0 {
                data.append(contentsOf: buffer.prefix(readCount))
            } else {
                #if os(macOS)
                logMacOSStreamReadFailure(
                    stage: "读取 HTTPS Request Body，期望=\(count) bytes，已读取=\(data.count) bytes",
                    stream: stream,
                    readResult: readCount,
                    receivedData: data
                )
                #endif
                throw AppWLocProxyError.httpRequestInvalid
            }
        }
        return data
    }

    #if os(macOS)
    private func logMacOSStreamReadFailure(
        stage: String,
        stream: InputStream,
        readResult: Int,
        receivedData: Data
    ) {
        let streamError = stream.streamError as NSError?
        AppWLocUtils.debugLog(
            [
                "\(AppWLocConfig.displayName) macOS TLS/HTTP 读取失败",
                "阶段：\(stage)",
                "read 返回：\(readResult)",
                "stream status：\(stream.streamStatus.rawValue)",
                "stream error：domain=\(streamError?.domain ?? "无")，code=\(streamError?.code ?? 0)，detail=\(streamError?.localizedDescription ?? "无")",
                "已收到大小：\(receivedData.count) bytes",
                "已收到 hex 前缀：\(formatHexPrefix(receivedData))"
            ].joined(separator: "\n")
        )
    }
    #endif

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let sent = send(fd, baseAddress.advanced(by: offset), data.count - offset, 0)
                if sent <= 0 {
                    throw AppWLocProxyError.upstreamFailed
                }
                offset += sent
            }
        }
    }

    private func writeAll(_ data: Data, to stream: OutputStream) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var offset = 0
            while offset < data.count {
                let written = stream.write(baseAddress.advanced(by: offset), maxLength: data.count - offset)
                if written <= 0 {
                    throw AppWLocProxyError.upstreamFailed
                }
                offset += written
            }
        }
    }

    private func configureTimeouts(_ fd: Int32) {
        var timeout = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

}

private struct AppWLocHTTPRequest {
    let method: String
    let host: String
    let path: String
    let url: URL
    let headers: [String: String]
    let body: Data
}

private struct AppWLocHTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}
