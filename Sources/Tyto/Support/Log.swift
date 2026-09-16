import os

nonisolated enum Log {
    static let subsystem = "com.yevhenii.tyto"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let debug = Logger(subsystem: subsystem, category: "debug")
}
