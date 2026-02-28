import Foundation

public enum Observability {
    public typealias Sink = (_ category: String, _ message: String) -> Void
    public static var sink: Sink?

    static func emit(category: String, message: String) {
        sink?(category, message)
    }
}
