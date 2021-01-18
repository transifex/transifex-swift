//
//  Logging.swift
//  Transifex
//
//  Created by Stelios Petrakis on 18/1/21.
//  Copyright © 2021 Transifex. All rights reserved.
//

import Foundation

/// Log levels used by TXStandardLogHandler to specify the severity of the logged message.
@objc
public enum TXLogLevel : Int8 {
    /// Verbose log message.
    case verbose = 1
    /// Info log message.
    case info = 2
    /// Warning log message.
    case warning = 3
    /// Error log message.
    case error = 4
}

/// Protocol that can be used to control all logging that occurs in the SDK
@objc
public protocol TXLogHandler {
    /// Logs an info message.
    /// - Parameter message: The info message
    func info(_ message: String)
    
    /// Logs a warning message.
    ///
    /// - Parameter message: The warning message
    func warning(_ message: String)
    
    /// Logs an error message.
    ///
    /// - Parameter message: The error message
    func error(_ message: String)
    
    /// Logs a verbose message.
    ///
    /// - Parameter message: The verbose message
    func verbose(_ message: String)
}

/// Class responsible for control logging in the SDK, allowing external log handlers
/// to be updated by SDK clients via the `TXLogHandler` protocol.
///
/// By default, TXLogger is initialized with a TXStandardLogHandler instance set to log
/// only warning and error log messages.
public final class TXLogger: NSObject {
    private var handler: TXLogHandler?
    
    fileprivate init(handler: TXLogHandler) {
        self.handler = handler
    }
    
    /// Updates the log handler of the SDK with an external class that conforms to
    /// the `TXLogHandler` protocol.
    ///
    /// - Parameter handler: The new log handler to be used
    @objc
    public static func setHandler(handler: TXLogHandler) {
        Logger.handler = handler
    }
    
    // Pragma: Delegate all log calls to the internal log handler.
    
    func info(_ message: String) {
        handler?.info(message)
    }
    
    func warning(_ message: String) {
        handler?.warning(message)
    }
    func error(_ message: String) {
        handler?.error(message)
    }
    func verbose(_ message: String) {
        handler?.verbose(message)
    }
}

/// Helper log handler that accepts a minimum allowed log level.
///
/// If the SDK tries to log a level lower that the one passed in the initialization,
/// then the message is not logged.
public class TXStandardLogHandler: NSObject {
    private var minLogLevel: TXLogLevel
    
    /// Initializes the standard log helper with a minimum log level.
    ///
    /// - Parameter minLogLevel: The minimum allowed log level
    @objc
    public init(_ minLogLevel: TXLogLevel) {
        self.minLogLevel = minLogLevel
    }
    
    private func log(_ message: String,
                     logLevel: TXLogLevel) {
        guard logLevel.rawValue >= self.minLogLevel.rawValue else {
            return
        }
        
        print(message)
    }
}

extension TXStandardLogHandler: TXLogHandler {
    public func verbose(_ message: String) { log(message, logLevel: .verbose) }
    public func info(_ message: String) { log(message, logLevel: .info) }
    public func warning(_ message: String) { log(message, logLevel: .warning) }
    public func error(_ message: String) { log(message, logLevel: .error) }
}

/// Internal global variable used throughout the SDK module.
///
/// Only error and warning log messages are logged in the console.
let Logger = TXLogger(handler: TXStandardLogHandler(.warning))
