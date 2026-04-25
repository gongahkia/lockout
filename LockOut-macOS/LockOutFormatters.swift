enum LockOutFormatters {
    static func clockTime(minutes: Int, seconds: Int) -> String {
        "\(twoDigit(minutes)):\(twoDigit(seconds))"
    }

    private static func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
