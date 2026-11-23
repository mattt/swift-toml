struct TOMLCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}

/// A type whose deprecated cases have a description.
///
/// A call through this protocol to a deprecated implementation
/// doesn't cause a deprecation warning.
protocol DeprecatedCaseDescribing {
    var deprecatedCaseDescription: String { get }
}
