//
//  LogCapture.swift
//  MeloNX
//
//  Created by Stossy11 on 22/09/2025.
//


import Foundation

final class LogCapture: ObservableObject {
    static let shared = LogCapture()

    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let originalStdout: Int32
    private let originalStderr: Int32

    private var continuation: AsyncStream<String>.Continuation?
    public private(set) var capturedLogs: [String] = []

    private let remoteLogQueue = DispatchQueue(label: "melonx.remote-log", qos: .utility)
    private var pendingRemoteLogs: [String] = []
    private var droppedRemoteLogs = 0
    private var remoteFlushScheduled = false

    private let remoteFlushInterval: TimeInterval = 0.75
    private let maxRemoteBatchSize = 40
    private let maxRemoteBufferSize = 500

    lazy var logs: AsyncStream<String> = {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in
                self.continuation = nil
            }
        }
    }()

    private init() {
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)
        startCapturing()
    }

    func startCapturing() {
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        redirectOutput(to: stdoutPipe!, fileDescriptor: STDOUT_FILENO)
        redirectOutput(to: stderrPipe!, fileDescriptor: STDERR_FILENO)

        setupReadabilityHandler(for: stdoutPipe!, isStdout: true)
        setupReadabilityHandler(for: stderrPipe!, isStdout: false)
    }

    func stopCapturing() {
        dup2(originalStdout, STDOUT_FILENO)
        dup2(originalStderr, STDERR_FILENO)

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func redirectOutput(to pipe: Pipe, fileDescriptor: Int32) {
        dup2(pipe.fileHandleForWriting.fileDescriptor, fileDescriptor)
    }

    private func setupReadabilityHandler(for pipe: Pipe, isStdout: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self else { return }

            let data = fileHandle.availableData
            let originalFD = isStdout ? self.originalStdout : self.originalStderr
            write(originalFD, (data as NSData).bytes, data.count)

            guard let logString = String(data: data, encoding: .utf8),
                  let cleanedLog = self.cleanLog(logString),
                  !cleanedLog.0.isEmpty else { return }

            self.capturedLogs.append(cleanedLog.1)
            self.continuation?.yield(cleanedLog.0) 
            self.enqueueRemoteLog(cleanedLog.1)

        }
    }

    private func enqueueRemoteLog(_ rawLine: String) {
        guard UserDefaults.standard.bool(forKey: "remoteLogEnabled") else {
            return
        }

        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return
        }

        remoteLogQueue.async { [weak self] in
            guard let self else { return }

            self.pendingRemoteLogs.append(line)

            if self.pendingRemoteLogs.count > self.maxRemoteBufferSize {
                let overflow = self.pendingRemoteLogs.count - self.maxRemoteBufferSize
                self.pendingRemoteLogs.removeFirst(overflow)
                self.droppedRemoteLogs += overflow
            }

            self.scheduleRemoteFlushLocked()
        }
    }

    private func scheduleRemoteFlushLocked() {
        if pendingRemoteLogs.count >= maxRemoteBatchSize {
            remoteFlushScheduled = false
            flushRemoteLogsLocked()
            return
        }

        guard !remoteFlushScheduled else {
            return
        }

        remoteFlushScheduled = true
        remoteLogQueue.asyncAfter(deadline: .now() + remoteFlushInterval) { [weak self] in
            guard let self else { return }
            self.remoteFlushScheduled = false
            self.flushRemoteLogsLocked()
        }
    }

    private func flushRemoteLogsLocked() {
        guard !pendingRemoteLogs.isEmpty else {
            return
        }

        guard let endpoint = remoteLogEndpoint() else {
            pendingRemoteLogs.removeAll(keepingCapacity: true)
            droppedRemoteLogs = 0
            return
        }

        let batchCount = min(maxRemoteBatchSize, pendingRemoteLogs.count)
        let batch = Array(pendingRemoteLogs.prefix(batchCount))
        pendingRemoteLogs.removeFirst(batchCount)

        let droppedCount = droppedRemoteLogs
        droppedRemoteLogs = 0

        let payload: [String: Any] = [
            "source": "melonx-ipados",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "dropped": droppedCount,
            "logs": batch,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { _, _, _ in
        }.resume()
    }

    private func remoteLogEndpoint() -> URL? {
        guard let rawValue = UserDefaults.standard.string(forKey: "remoteLogEndpoint")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    private func cleanLog(_ raw: String) -> (String, String)? {
        let lines = raw.split(separator: "\n")
        
        let filteredLines = lines.filter { line in
            if UserDefaults.standard.bool(forKey: "showFullLogs") {
                return true
            }
            
            let regex = try? NSRegularExpression(pattern: "\\d{2}:\\d{2}:\\d{2}\\.\\d{3} \\|[A-Z]+\\|", options: .caseInsensitive)
            let matches = regex?.matches(in: String(line), options: [], range: NSRange(location: 0, length: line.utf16.count)) ?? []
            
            return matches.count >= 1
        }

        let cleaned = filteredLines.map { line -> String in
            if let tabRange = line.range(of: "\t") {
                return line[tabRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n")
        
        
        let cleaned2 = lines.map { line -> String in
            if let tabRange = line.range(of: "\t") {
                return line[tabRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n")

        return cleaned.isEmpty ? nil : (cleaned.replacingOccurrences(of: "\n\n", with: "\n"), cleaned2)
    }

    deinit {
        stopCapturing()
        continuation?.finish()
    }
}
