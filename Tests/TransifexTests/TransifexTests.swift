import XCTest
@testable import Transifex

/// Partially mocked URLSessionDataTask and URLSession classes so that we can test how
/// Transifex behaves on certain server responses.
class URLSessionDataTaskMock: URLSessionDataTask {
    private let closure: () -> Void

    init(closure: @escaping () -> Void) {
        self.closure = closure
    }

    override func resume() {
        closure()
    }
}

struct MockResponse {
    var url : URL
    var data : Data?
    var statusCode : Int?
    var error : Error?
}

class URLSessionMock: URLSession {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void

    var mockResponses : [MockResponse]?
    var mockResponseIndex = 0
    
    override init() { }
    
    override func dataTask(
        with request: URLRequest,
        completionHandler: @escaping CompletionHandler
    ) -> URLSessionDataTask {
        guard
            let requestURL = request.url,
            let mockResponse = mockResponses?[mockResponseIndex],
            mockResponse.url == requestURL else {
            return URLSessionDataTaskMock {
                completionHandler(nil, nil, nil)
            }
        }
        
        mockResponseIndex += 1
        
        let data = mockResponse.data
        let error = mockResponse.error
        
        return URLSessionDataTaskMock {
            let response = HTTPURLResponse(url: requestURL,
                                           statusCode: mockResponse.statusCode ?? 200,
                                           httpVersion: nil,
                                           headerFields: nil)
            completionHandler(data, response, error)
        }
    }
}

class MockLocaleProvider : TXCurrentLocaleProvider {
    private var mockLocaleCode : String
    
    init(_ mockLocaleCode: String) {
        self.mockLocaleCode = mockLocaleCode
    }
    
    func currentLocale() -> String {
        return self.mockLocaleCode
    }
}

class MockCacheProvider : TXCacheProvider {
    let translations: TXTranslations?
    
    init(translations: TXTranslations) {
        self.translations = translations
    }
    
    func getTranslations() -> TXTranslations? {
        return translations
    }
}

class MockErrorPolicy : TXErrorPolicy {
    func get(sourceString: String,
             stringToRender: String,
             localeCode: String,
             params: [String : Any]) throws -> String {
        return "MOCKERROR"
    }
}

class MockErrorPolicyException : TXErrorPolicy {
    enum MockError: Error {
        case generic
    }
    
    func get(sourceString: String,
             stringToRender: String,
             localeCode: String,
             params: [String : Any]) throws -> String {
        throw MockError.generic
    }
}

final class TransifexTests: XCTestCase {
    static let testToken = "<token>"

    override func tearDown() {
        TXNative.dispose()
    }
    
    func testDuplicateLocaleFiltering() {
        let duplicateLocales = [ "en", "fr", "en" ]
        
        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: duplicateLocales)
        
        let expectedAppLocales = [ "en", "fr" ]
        
        // We test the sorted arrays, in case the `TXLocaleState` initializer
        // has resorted the passed array.
        XCTAssertEqual(localeState.appLocales.sorted(),
                       expectedAppLocales.sorted())
    }
    
    func testCurrentLocaleProvider() {
        let mockCode = "mock_code"
        let mockLocaleProvider = MockLocaleProvider(mockCode)
        let localeState = TXLocaleState(sourceLocale: nil,
                                        appLocales: [],
                                        currentLocaleProvider: mockLocaleProvider)
        
        XCTAssertEqual(localeState.currentLocale, mockCode)
    }
    
    func testEncodingSourceStringMeta() {
        let sourceStringMeta = SourceStringMeta(context: ["test"],
                                                comment: "Test comment",
                                                characterLimit: 10,
                                                tags: ["test"])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try! encoder.encode(sourceStringMeta)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        let expectedJsonString = "{\"character_limit\":10,\"context\":[\"test\"],\"developer_comment\":\"Test comment\",\"tags\":[\"test\"]}"
        
        XCTAssertEqual(jsonString, expectedJsonString)
    }
    
    func testEncodingSourceString() {
        let sourceString = SourceString(string:"test string",
                                        key:"testkey")
        
        let jsonData = try! JSONEncoder().encode(sourceString)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        let expectedJsonString = "{\"string\":\"test string\"}"
        
        XCTAssertEqual(jsonString, expectedJsonString)
    }
    
    func testEncodingSourceStringWithMeta() {
        let sourceStringMeta = SourceStringMeta(context: ["test"],
                                                comment: "Test comment",
                                                characterLimit: 10,
                                                tags: ["test"])
        let sourceString = SourceString(string:"test string",
                                        key:"testkey",
                                        meta: sourceStringMeta)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try! encoder.encode(sourceString)
        let jsonString = String(data: jsonData, encoding: .utf8)

        let expectedJsonString = "{\"meta\":{\"character_limit\":10,\"context\":[\"test\"],\"developer_comment\":\"Test comment\",\"tags\":[\"test\"]},\"string\":\"test string\"}"
        
        XCTAssertEqual(jsonString, expectedJsonString)
    }
    
    func testExtractMultipleICUPlurals() {
        XCTAssertEqual(
            "There {term1, plural, one {is %d person} other {are %d people}} sitting in {term2, plural, one {%d table} two {a couple of tables} other {%d tables}} in this restaurant".extractICUPlurals(),
            [
                "{term1, plural, one {is %d person} other {are %d people}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "is %d person",
                                    .other: "are %d people"
                                ]),
                "{term2, plural, one {%d table} two {a couple of tables} other {%d tables}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%d table",
                                    .two: "a couple of tables",
                                    .other: "%d tables"
                                ])
            ]
        )
    }

    func testExtractICUPlurals() {
        XCTAssertEqual(
            "{???, plural, one {One table} two {A couple of tables} other {%d tables}}".extractICUPlurals(),
            [
                "{???, plural, one {One table} two {A couple of tables} other {%d tables}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "One table",
                                    .two: "A couple of tables",
                                    .other: "%d tables"
                                ])
            ]
        )
        XCTAssertEqual(
            "{cnt, plural, other {%d tables}}".extractICUPlurals(),
            [
                "{cnt, plural, other {%d tables}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .other: "%d tables"
                                ])
            ]
        )
        XCTAssertEqual("{cnt, plural, }".extractICUPlurals(), [:])
        XCTAssertEqual("{something}".extractICUPlurals(), [:])
    }

    func testPlatformFormatMultiple() {
        // As per documentation [^1]:
        //
        // > The meaning of the plural categories is language-dependent, and
        // > not all languages have the same categories.
        // > For example, the English language only requires the one and other
        // > categories to represent plural forms, and zero is optional.
        // > Arabic has different plural forms for the zero, one, two, few,
        // > many, and other categories.
        // > Although Russian also uses the many category, the rules for which
        // > numbers are in the many category aren’t the same as the Arabic
        // > rules.
        //
        // [^1]: https://developer.apple.com/documentation/xcode/localizing-strings-that-contain-plurals#Localize-the-strings-dictionary-file-in-the-development-language

        XCTAssertEqual(try PlatformFormat.format(stringToRender: "There %1$#@{term1, plural, one {is %d person} other {are %d people}}@ sitting in %2$#@{term2, plural, one {%d table} two {a couple of tables} other {%d tables}}@ in this restaurant.",
                                                 localeCode: "en",
                                                 params: [Swizzler.PARAM_ARGUMENTS_KEY: [3,5]]),
                       "There are 3 people sitting in 5 tables in this restaurant.")

        XCTAssertEqual(try PlatformFormat.format(stringToRender: "There %1$#@{term1, plural, zero {is noone} one {is %d person} other {are %d people}}@ sitting in %2$#@{term2, plural, zero {any tables} one {%d table} other {%d tables}}@ in this restaurant",
                                                 localeCode: "en",
                                                 params: [Swizzler.PARAM_ARGUMENTS_KEY: [0,0]]),
                       "There is noone sitting in any tables in this restaurant")

        XCTAssertEqual(try PlatformFormat.format(stringToRender: "There %1$#@{term1, plural, zero {is noone} one {is %d person} other {are %d people}}@ sitting in %2$#@{term2, plural, one {%d table} other {%d tables}}@ in this restaurant",
                                                 localeCode: "en",
                                                 params: [Swizzler.PARAM_ARGUMENTS_KEY: [0,2]]),
                       "There is noone sitting in 2 tables in this restaurant")

        // Two rule works in Arabic locale, not in English
        XCTAssertEqual(try PlatformFormat.format(stringToRender: "There %1$#@{term1, plural, zero {is noone} one {is %d person} other {are %d people}}@ sitting in %2$#@{term2, plural, one {%d table} two {a couple of tables} other {%d tables}}@ in this restaurant",
                                                 localeCode: "ar",
                                                 params: [Swizzler.PARAM_ARGUMENTS_KEY: [0,2]]),
                       "There is noone sitting in a couple of tables in this restaurant")
    }

    func testPlatformFormat() {
        XCTAssertEqual(try PlatformFormat.format(stringToRender: "{cnt, plural, one {One table} other {%d tables}}",
                                             localeCode: "en",
                                             params: [Swizzler.PARAM_ARGUMENTS_KEY: [1]]),
                       "One table")
    }

    func testTXNativeFetchTranslationsWithStatus() {
        let mockResponse1 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Bstatus%5D=translated")!,
                                         data: "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8))
        
        let mockResponse2 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Bstatus%5D=reviewed")!,
                                         data: "{\"data\":{\"testkey3\":{\"string\":\"test string 3\"}}}".data(using: .utf8))

        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponse1,
            mockResponse2
        ]

        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["en"])
        TXNative.initialize(locales: localeState,
                            token: Self.testToken,
                            session: urlSession,
                            filterStatus: "translated")

        let expectation1 = self.expectation(description: "Waiting for translated translations to be fetched")
        var translationErrors : [Error]? = nil
        var translationsStructure : TXTranslations? = nil

        TXNative.fetchTranslations() { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 2)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey1"])
            XCTAssertNotNil(translationsStructure?["en"]?["testkey2"])
        }

        let expectation2 = self.expectation(description: "Waiting for reviewed translations to be fetched as an override")
        translationErrors = nil
        translationsStructure = nil

        TXNative.fetchTranslations(status: "reviewed") { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 1)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey3"])
        }
    }

    func testTXNativeFetchTranslationsWithTags() {
        let mockResponse1 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Btags%5D=ios")!,
                                         data: "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8))

        let mockResponse2 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Btags%5D=android")!,
                                         data: "{\"data\":{\"testkey3\":{\"string\":\"test string 3\"}}}".data(using: .utf8))

        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponse1,
            mockResponse2 ]

        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["en"])
        TXNative.initialize(locales: localeState,
                            token: Self.testToken,
                            session: urlSession,
                            filterTags: ["ios"])

        let expectation1 = self.expectation(description: "Waiting for iOS translations to be fetched")
        var translationErrors : [Error]? = nil
        var translationsStructure : TXTranslations? = nil

        TXNative.fetchTranslations() { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 2)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey1"])
            XCTAssertNotNil(translationsStructure?["en"]?["testkey2"])
        }

        let expectation2 = self.expectation(description: "Waiting for Android translations to be fetched as an override")
        translationErrors = nil
        translationsStructure = nil

        TXNative.fetchTranslations(tags: ["android"]) { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 1)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey3"])
        }
    }

    func testCDSHandlerFetchTranslationsWithStatus() {
        let mockResponse1 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Bstatus%5D=translated")!,
                                         data: "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8))

        let mockResponse2 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Bstatus%5D=reviewed")!,
                                         data: "{\"data\":{\"testkey3\":{\"string\":\"test string 3\"}}}".data(using: .utf8))

        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponse1,
            mockResponse2
        ]

        let cdsConfiguration = CDSConfiguration(localeCodes: [ "en" ],
                                                token: Self.testToken)
        let cdsHandler = CDSHandler(configuration: cdsConfiguration,
                                    session: urlSession)

        let expectation1 = self.expectation(description: "Waiting for translated translations to be fetched")
        var translationErrors : [Error]? = nil
        var translationsStructure : TXTranslations? = nil

        cdsHandler.fetchTranslations(status: "translated") { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 2)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey1"])
            XCTAssertNotNil(translationsStructure?["en"]?["testkey2"])
        }

        let expectation2 = self.expectation(description: "Waiting for reviewed translations to be fetched")
        translationErrors = nil
        translationsStructure = nil

        cdsHandler.fetchTranslations(status: "reviewed") { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 1)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey3"])
        }
    }

    func testCDSHandlerFetchTranslationsWithTags() {
        let mockResponse1 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Btags%5D=ios")!,
                                         data: "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8))

        let mockResponse2 = MockResponse(url: URL(string: "https://cds.svc.transifex.net/content/en?filter%5Btags%5D=android")!,
                                         data: "{\"data\":{\"testkey3\":{\"string\":\"test string 3\"}}}".data(using: .utf8))

        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponse1,
            mockResponse2
        ]

        let cdsConfiguration = CDSConfiguration(localeCodes: [ "en" ],
                                                token: Self.testToken)
        let cdsHandler = CDSHandler(configuration: cdsConfiguration,
                                    session: urlSession)

        let expectation1 = self.expectation(description: "Waiting for iOS translations to be fetched")
        var translationErrors : [Error]? = nil
        var translationsStructure : TXTranslations? = nil
        
        cdsHandler.fetchTranslations(tags: ["ios"]) { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 2)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey1"])
            XCTAssertNotNil(translationsStructure?["en"]?["testkey2"])
        }

        let expectation2 = self.expectation(description: "Waiting for Android translations to be fetched")
        translationErrors = nil
        translationsStructure = nil

        cdsHandler.fetchTranslations(tags: ["android"]) { translations, errors in
            translationsStructure = translations
            translationErrors = errors
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
            XCTAssertNotNil(translationsStructure)
            XCTAssertTrue(translationsStructure?["en"]?.count == 1)
            XCTAssertNotNil(translationsStructure?["en"]?["testkey3"])
        }
    }
    
    func testFetchTranslations() {
        let expectation = self.expectation(description: "Waiting for translations to be fetched")
        var translationsResult : TXTranslations? = nil
        
        let mockResponseData = "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8)
        let expectedURL = URL(string: "https://cds.svc.transifex.net/content/en")!
        
        let mockResponse = MockResponse(url: expectedURL,
                                        data: mockResponseData,
                                        statusCode: 200)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [mockResponse]
        
        let cdsConfiguration = CDSConfiguration(localeCodes: [ "en" ],
                                                token: Self.testToken)
        let cdsHandler = CDSHandler(configuration: cdsConfiguration,
                                    session: urlSession)
        
        cdsHandler.fetchTranslations { (translations, errors) in
            translationsResult = translations
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationsResult)
            XCTAssertNotNil(translationsResult!["en"])
            XCTAssertNotNil(translationsResult!["en"]!["testkey1"])
            XCTAssertEqual(translationsResult!["en"]!["testkey1"]!["string"], "test string 1")
            XCTAssertNotNil(translationsResult!["en"]!["testkey2"])
            XCTAssertEqual(translationsResult!["en"]!["testkey2"]!["string"], "test string 2")
        }
    }
    
    func testFetchTranslationsNotReady() {
        let expectation = self.expectation(description: "Waiting for translations to be fetched")
        var translationsResult : TXTranslations? = nil
        
        let mockResponseData = "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8)
        let expectedURL = URL(string: "https://cds.svc.transifex.net/content/en")!
        
        let mockResponseNotReady = MockResponse(url: expectedURL,
                                                statusCode: 202)
        let mockResponseReady = MockResponse(url: expectedURL,
                                             data: mockResponseData,
                                             statusCode: 200)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponseNotReady,
            mockResponseNotReady,
            mockResponseReady
        ]
        
        let cdsConfiguration = CDSConfiguration(localeCodes: [ "en" ],
                                                token: Self.testToken)
        let cdsHandler = CDSHandler(configuration: cdsConfiguration,
                                    session: urlSession)
        
        cdsHandler.fetchTranslations { (translations, errors) in
            translationsResult = translations
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationsResult)
            XCTAssertNotNil(translationsResult!["en"])
            XCTAssertNotNil(translationsResult!["en"]!["testkey1"])
            XCTAssertEqual(translationsResult!["en"]!["testkey1"]!["string"], "test string 1")
            XCTAssertNotNil(translationsResult!["en"]!["testkey2"])
            XCTAssertEqual(translationsResult!["en"]!["testkey2"]!["string"], "test string 2")
        }
    }
    
    func testPushTranslations() {
        let expectation = self.expectation(description: "Waiting for translations to be pushed")
        let translations = [
            TXSourceString(key: "testkey",
                           sourceString: "sourceString",
                           occurrences: [],
                           characterLimit: 0)
        ]
        
        let expectedDataString = "{\"data\":{\"id\":\"123\",\"links\":{\"job\":\"/jobs/content/456\"}}}"
        let expectedURL = URL(string: "https://cds.svc.transifex.net/content")!
        
        let mockResponse = MockResponse(url: expectedURL,
                                        data: expectedDataString.data(using: .utf8),
                                        statusCode: 202)
        
        let expectedJobDataString = "{\"data\":{\"details\":{\"created\":1,\"updated\":0,\"skipped\":0,\"deleted\":0,\"failed\":0},\"errors\":[],\"status\":\"completed\"}}"
        let expectedJobURL = URL(string: "https://cds.svc.transifex.net/jobs/content/456")!
        
        let mockJobResponse = MockResponse(url: expectedJobURL,
                                           data: expectedJobDataString.data(using: .utf8),
                                           statusCode: 200)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [ mockResponse, mockJobResponse ]
        let cdsConfiguration = CDSConfiguration(localeCodes: [ "en" ],
                                                token: Self.testToken)
        let cdsHandler = CDSHandler(configuration: cdsConfiguration,
                                    session: urlSession)
        
        var pushResult = false
        cdsHandler.pushTranslations(translations) { (result, errors, warnings) in
            pushResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertTrue(pushResult)
        }
    }
    
    func testPushTranslationsNotReady() {
        let expectation = self.expectation(description: "Waiting for translations to be pushed")
        let translations = [
            TXSourceString(key: "testkey",
                           sourceString: "sourceString",
                           occurrences: [],
                           characterLimit: 0)
        ]
        
        let expectedDataString = "{\"data\":{\"id\":\"123\",\"links\":{\"job\":\"/jobs/content/456\"}}}"
        let expectedURL = URL(string: "https://cds.svc.transifex.net/content")!
        
        let mockResponse = MockResponse(url: expectedURL,
                                        data: expectedDataString.data(using: .utf8),
                                        statusCode: 202)
        
        let expectedJobURL = URL(string: "https://cds.svc.transifex.net/jobs/content/456")!

        let expectedPendingJobDataString = "{\"data\":{\"status\":\"pending\"}}"
        let mockPendingJobResponse = MockResponse(url: expectedJobURL,
                                           data: expectedPendingJobDataString.data(using: .utf8),
                                           statusCode: 200)
        
        let expectedProcessingJobDataString = "{\"data\":{\"status\":\"processing\"}}"
        let mockProcessingJobResponse = MockResponse(url: expectedJobURL,
                                           data: expectedProcessingJobDataString.data(using: .utf8),
                                           statusCode: 200)
        
        let expectedCompletedJobDataString = "{\"data\":{\"details\":{\"created\":1,\"updated\":0,\"skipped\":0,\"deleted\":0,\"failed\":0},\"errors\":[],\"status\":\"completed\"}}"
        let mockCompletedJobResponse = MockResponse(url: expectedJobURL,
                                                    data: expectedCompletedJobDataString.data(using: .utf8),
                                                    statusCode: 200)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponse,
            mockPendingJobResponse,
            mockPendingJobResponse,
            mockPendingJobResponse,
            mockPendingJobResponse,
            mockPendingJobResponse,
            mockProcessingJobResponse,
            mockProcessingJobResponse,
            mockProcessingJobResponse,
            mockProcessingJobResponse,
            mockProcessingJobResponse,
            mockCompletedJobResponse
        ]
        let cdsConfiguration = CDSConfiguration(localeCodes: [ "en" ],
                                                token: Self.testToken)
        let cdsHandler = CDSHandler(configuration: cdsConfiguration,
                                    session: urlSession)
        
        var pushResult = false
        cdsHandler.pushTranslations(translations) { (result, errors, warnings) in
            pushResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertTrue(pushResult)
        }
    }
    
    func testReplaceAllPolicy() {
        let existingTranslations: TXTranslations = [
            "en": [
                "a": [ "string": "a" ],
                "b": [ "string": "b" ],
                "c": [ "string": "c" ],
                "d": [ "string": "" ],
                "e": [ "string": "" ]
            ]
        ]
        
        let memoryCache =  TXMemoryCache()
        memoryCache.update(translations: existingTranslations)
        
        let newTranslations: TXTranslations = [
            "en": [
                "b": [ "string": "B" ],
                "c": [ "string": "" ],
                "e": [ "string": "E" ],
                "f": [ "string": "F" ],
                "g": [ "string": "" ]
            ]
        ]
        let provider = MockCacheProvider(translations: newTranslations)

        let cache = TXProviderBasedCache(
            providers: [ provider ],
            internalCache: TXStringUpdateFilterCache(
                policy: .replaceAll,
                internalCache: memoryCache
            )
        )
        
        XCTAssertNil(cache.get(key: "a", localeCode: "en"))
        XCTAssertEqual(cache.get(key: "b", localeCode: "en"), "B")
        XCTAssertEqual(cache.get(key: "c", localeCode: "en"), "")
        XCTAssertNil(cache.get(key: "d", localeCode: "en"))
        XCTAssertEqual(cache.get(key: "e", localeCode: "en"), "E")
        XCTAssertEqual(cache.get(key: "f", localeCode: "en"), "F")
        XCTAssertEqual(cache.get(key: "g", localeCode: "en"), "")
    }
    
    func testUpdateUsingTranslatePolicy() {
        let existingTranslations: TXTranslations = [
            "en": [
                "a": [ "string": "a" ],
                "b": [ "string": "b" ],
                "c": [ "string": "c" ],
                "d": [ "string": "" ],
                "e": [ "string": "" ]
            ]
        ]
        
        let memoryCache =  TXMemoryCache()
        memoryCache.update(translations: existingTranslations)
        
        let newTranslations: TXTranslations = [
            "en": [
                "b": [ "string": "B" ],
                "c": [ "string": "" ],
                "e": [ "string": "E" ],
                "f": [ "string": "F" ],
                "g": [ "string": "" ]
            ]
        ]
        let provider = MockCacheProvider(translations: newTranslations)

        let cache = TXProviderBasedCache(
            providers: [ provider ],
            internalCache: TXStringUpdateFilterCache(
                policy: .updateUsingTranslated,
                internalCache: memoryCache
            )
        )
        
        XCTAssertEqual(cache.get(key: "a", localeCode: "en"), "a")
        XCTAssertEqual(cache.get(key: "b", localeCode: "en"), "B")
        XCTAssertEqual(cache.get(key: "c", localeCode: "en"), "c")
        XCTAssertEqual(cache.get(key: "d", localeCode: "en"), "")
        XCTAssertEqual(cache.get(key: "e", localeCode: "en"), "E")
        XCTAssertEqual(cache.get(key: "f", localeCode: "en"), "F")
        XCTAssertNil(cache.get(key: "g", localeCode: "en"))
    }
    
    func testReadOnlyCache() {
        let existingTranslations: TXTranslations = [
            "en": [
                "a": [ "string": "a" ],
                "b": [ "string": "b" ],
                "c": [ "string": "c" ],
                "d": [ "string": "" ],
                "e": [ "string": "" ]
            ]
        ]
        
        let memoryCache =  TXMemoryCache()
        memoryCache.update(translations: existingTranslations)
        
        let newTranslations: TXTranslations = [
            "en": [
                "b": [ "string": "B" ],
                "c": [ "string": "" ],
                "e": [ "string": "E" ],
                "f": [ "string": "F" ]
            ]
        ]
        let provider = MockCacheProvider(translations: newTranslations)

        let cache = TXProviderBasedCache(
            providers: [ provider ],
            internalCache: TXStringUpdateFilterCache(
                policy: .updateUsingTranslated,
                internalCache: TXReadonlyCacheDecorator(internalCache: memoryCache)
            )
        )
        
        XCTAssertEqual(cache.get(), existingTranslations)
    }
    
    func testPlatformStrategyWithInvalidSourceString() {
        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["fr"])
        
        let core = NativeCore(locales: localeState,
                              token: Self.testToken,
                              secret: nil,
                              cdsHost: nil,
                              cache: nil,
                              renderingStrategy: .platform)
        
        let result = core.render(sourceString: "test", stringToRender: nil, localeCode: "", params: [
                        Swizzler.PARAM_ARGUMENTS_KEY: [1, 2] as [CVarArg]
        ])
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "test")
    }
    
    func testErrorPolicy() {
        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["fr"])
        
        TXNative.initialize(locales: localeState,
                            token: Self.testToken,
                            errorPolicy: MockErrorPolicy(),
                            renderingStrategy: .icu)
        
        let result = TXNative.translate(sourceString: "source string", params: [:], context: nil)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, "MOCKERROR")
    }
    
    func testErrorPolicyException() {
        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["fr"])
        
        TXNative.initialize(locales: localeState,
                            token: Self.testToken,
                            errorPolicy: MockErrorPolicyException(),
                            renderingStrategy: .icu)
        
        let result = TXNative.translate(sourceString: "source string", params: [:], context: nil)

        XCTAssertEqual(result, "ERROR")
    }

    func testCurrentLocaleNotFirstPreference() {
        let appleLanguagesKey = "AppleLanguages"
        let storedLanguages = UserDefaults.standard.value(forKey: appleLanguagesKey)
        
        UserDefaults.standard.set([ "nl", "fr" ],
                                  forKey: appleLanguagesKey)
        
        let locale = TXLocaleState(sourceLocale: "en",
                                   appLocales: [ "fr", "de", "es", "it"])
        
        XCTAssertEqual(locale.currentLocale,
                       "fr")
        
        UserDefaults.standard.set(storedLanguages,
                                  forKey: appleLanguagesKey)
    }
    
    func testCurrentLocaleNotAnyPreference() {
        let appleLanguagesKey = "AppleLanguages"
        let storedLanguages = UserDefaults.standard.value(forKey: appleLanguagesKey)
        
        UserDefaults.standard.set([ "nl", "fr" ],
                                  forKey: appleLanguagesKey)
        
        let locale = TXLocaleState(sourceLocale: "en",
                                   appLocales: [ "de", "es", "it"])
        
        XCTAssertEqual(locale.currentLocale,
                       "en")
        
        UserDefaults.standard.set(storedLanguages,
                                  forKey: appleLanguagesKey)
    }
    
    func testSourceLocalePosition() {
        let locale = TXLocaleState(sourceLocale: "en",
                                   appLocales: [ "fr", "el" ])
        
        XCTAssertTrue(locale.appLocales.first == "en")
    }
    
    func testTranslateWithSourceStringsInCache() {
        let sourceLocale = "en"
        let localeState = TXLocaleState(sourceLocale: sourceLocale,
                                        appLocales: [
                                            sourceLocale,
                                            "el"])
        
        
        let sourceStringTest = "tx_test_key"
        let translatedStringTest = "test updated"
        
        let sourceStringPlural = "tx_plural_test_key"
        let translatedStringPluralOne = "car updated"
        let translatedStringPluralOther = "cars updated"
        let translatedStringPluralRule = "{cnt, plural, one {\(translatedStringPluralOne)} other {\(translatedStringPluralOther)}}"
        
        let keyTest = txGenerateKey(sourceString: sourceStringTest, context: nil)
        let keyPlural = txGenerateKey(sourceString: sourceStringPlural, context: nil)
        
        let existingTranslations: TXTranslations = [
            sourceLocale: [
                keyTest: [ "string": translatedStringTest ],
                keyPlural : [ "string": translatedStringPluralRule ]
            ]
        ]
        
        let memoryCache =  TXMemoryCache()
        memoryCache.update(translations: existingTranslations)
        
        TXNative.initialize(locales: localeState,
                            token: Self.testToken,
                            cache: memoryCache)
        
        let result = TXNative.translate(sourceString: sourceStringTest,
                                        params: [:],
                                        context: nil)
        
        XCTAssertEqual(result, translatedStringTest)
        
        let pluralsResultOne = TXNative.translate(sourceString: sourceStringPlural,
                                                  params: [
                                                    Swizzler.PARAM_ARGUMENTS_KEY: [1 as CVarArg]],
                                                  context: nil)
        
        XCTAssertEqual(pluralsResultOne, translatedStringPluralOne)
        
        let pluralsResultOther = TXNative.translate(sourceString: sourceStringPlural,
                                                    params: [
                                                        Swizzler.PARAM_ARGUMENTS_KEY: [3 as CVarArg]],
                                                    context: nil)
        
        XCTAssertEqual(pluralsResultOther, translatedStringPluralOther)
    }

    func testXMLPluralParserDeviceVariation() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="device.applevision">This is Apple Vision</cds-unit><cds-unit id="device.applewatch">This is an Apple Watch</cds-unit><cds-unit id="device.iphone">This is an iPhone</cds-unit><cds-unit id="device.mac">This is a Mac</cds-unit><cds-unit id="device.other">This is a device</cds-unit></cds-root>
""", deviceName: "mac")
        XCTAssertEqual(parseResult, "This is a Mac")
    }

    func testXMLPluralParserDeviceVariationiPadFallbackiPhone() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="device.applevision">This is Apple Vision</cds-unit><cds-unit id="device.applewatch">This is an Apple Watch</cds-unit><cds-unit id="device.iphone">This is an iPhone</cds-unit><cds-unit id="device.mac">This is a Mac</cds-unit><cds-unit id="device.other">This is a device</cds-unit></cds-root>
""", deviceName: "ipad")
        XCTAssertEqual(parseResult, "This is an iPhone")
    }

    func testXMLPluralParserDeviceVariationiPadFallbackOther() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="device.applevision">This is Apple Vision</cds-unit><cds-unit id="device.applewatch">This is an Apple Watch</cds-unit><cds-unit id="device.ipod">This is an iPhone</cds-unit><cds-unit id="device.mac">This is a Mac</cds-unit><cds-unit id="device.other">This is a device</cds-unit></cds-root>
""", deviceName: "ipad")
        XCTAssertEqual(parseResult, "This is a device")
    }

    func testXMLPluralParserDevicePluralVariation() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="device.iphone.plural.one">iPhone has %d item</cds-unit><cds-unit id="device.iphone.plural.other">iPhone has %d items</cds-unit><cds-unit id="device.mac">Mac has %d items</cds-unit><cds-unit id="device.other">We have %d items</cds-unit></cds-root>
""",
                                                  deviceName: "iphone")
        XCTAssertEqual(parseResult, "{???, plural, one {iPhone has %d item} other {iPhone has %d items}}")
    }

    func testXMLPluralParserSimpleSubstitutions() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="substitutions">Found %1$#@arg1@ having %2$#@arg2@</cds-unit><cds-unit id="substitutions.arg1.plural.one">%1$ld user</cds-unit><cds-unit id="substitutions.arg1.plural.other">%1$ld users</cds-unit><cds-unit id="substitutions.arg2.plural.one">%2$ld device</cds-unit><cds-unit id="substitutions.arg2.plural.other">%2$ld devices</cds-unit></cds-root>
""")
        XCTAssertEqual(parseResult, "Found %1$#@{arg1, plural, one {%ld user} other {%ld users}}@ having %2$#@{arg2, plural, one {%ld device} other {%ld devices}}@")

        XCTAssertEqual(
            parseResult!.extractICUPlurals(),
            [
                "{arg1, plural, one {%ld user} other {%ld users}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld user",
                                    .other: "%ld users"
                                ]),
                "{arg2, plural, one {%ld device} other {%ld devices}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld device",
                                    .other: "%ld devices"
                                ])
            ]
        )
    }
    
    func testXMLPluralParserSimpleSubstitutionsStringsDict() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="substitutions">Found %#@arg1@ having %#@arg2@</cds-unit><cds-unit id="substitutions.arg1.plural.one">%ld user</cds-unit><cds-unit id="substitutions.arg1.plural.other">%ld users</cds-unit><cds-unit id="substitutions.arg2.plural.one">%ld device</cds-unit><cds-unit id="substitutions.arg2.plural.other">%ld devices</cds-unit></cds-root>
""")
        XCTAssertEqual(parseResult, "Found %1$#@{arg1, plural, one {%ld user} other {%ld users}}@ having %2$#@{arg2, plural, one {%ld device} other {%ld devices}}@")

        XCTAssertEqual(
            parseResult!.extractICUPlurals(),
            [
                "{arg1, plural, one {%ld user} other {%ld users}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld user",
                                    .other: "%ld users"
                                ]),
                "{arg2, plural, one {%ld device} other {%ld devices}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld device",
                                    .other: "%ld devices"
                                ])
            ]
        )
    }

    func testXMLPluralParserSimpleSubstitutionsStringsDictAlt() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="substitutions">%#@num_people_in_room@ in %#@room@</cds-unit><cds-unit id="substitutions.num_people_in_room.plural.one">Only %d person</cds-unit><cds-unit id="substitutions.num_people_in_room.plural.other">Some people</cds-unit><cds-unit id="substitutions.num_people_in_room.plural.zero">No people</cds-unit><cds-unit id="substitutions.room.plural.one">%d room</cds-unit><cds-unit id="substitutions.room.plural.other">%d rooms</cds-unit><cds-unit id="substitutions.room.plural.zero">no room</cds-unit></cds-root>
""")
        XCTAssertEqual(parseResult, "%1$#@{num_people_in_room, plural, one {Only %d person} other {Some people} zero {No people}}@ in %2$#@{room, plural, one {%d room} other {%d rooms} zero {no room}}@")

        XCTAssertEqual(
            parseResult!.extractICUPlurals(),
            [
                "{num_people_in_room, plural, one {Only %d person} other {Some people} zero {No people}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "Only %d person",
                                    .other: "Some people",
                                    .zero: "No people"
                                ]),
                "{room, plural, one {%d room} other {%d rooms} zero {no room}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%d room",
                                    .other: "%d rooms",
                                    .zero: "no room"
                                ])
            ]
        )
    }

    func testXMLPluralParserDeviceAndSubstitutions() {
        let parseResult = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id="device.iphone">This iPhone contains %1$#@user_iphone@ with %2$#@folder_iphone@ </cds-unit><cds-unit id="device.mac">This Mac contains %1$#@user_mac@ with %2$#@folder_mac@ </cds-unit><cds-unit id="substitutions.folder_iphone.plural.one">%2$ld folder</cds-unit><cds-unit id="substitutions.folder_iphone.plural.other">%2$ld folders</cds-unit><cds-unit id="substitutions.folder_mac.plural.one">%2$ld folder</cds-unit><cds-unit id="substitutions.folder_mac.plural.other">%2$ld folders</cds-unit><cds-unit id="substitutions.user_iphone.plural.one">%1$ld user</cds-unit><cds-unit id="substitutions.user_iphone.plural.other">%1$ld users</cds-unit><cds-unit id="substitutions.user_mac.plural.one">%1$ld user</cds-unit><cds-unit id="substitutions.user_mac.plural.other">%1$ld users</cds-unit></cds-root>
""",
                                                  deviceName: "mac")
        XCTAssertEqual(parseResult, "This Mac contains %1$#@{user_mac, plural, one {%ld user} other {%ld users}}@ with %2$#@{folder_mac, plural, one {%ld folder} other {%ld folders}}@ ")

        XCTAssertEqual(
            parseResult!.extractICUPlurals(),
            [
                "{user_mac, plural, one {%ld user} other {%ld users}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld user",
                                    .other: "%ld users"
                                ]),
                "{folder_mac, plural, one {%ld folder} other {%ld folders}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld folder",
                                    .other: "%ld folders"
                                ])
            ]
        )
    }

    func testXMLDeviceSubstitutionSpecial() {
        let parseResult1 = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id=\"device.iphone\">Device has %1$#@arg1_iphone@ in %2$ld folders</cds-unit><cds-unit id=\"device.other\">Device has %ld users in %ld folders</cds-unit><cds-unit id=\"substitutions.arg1_iphone.plural.one\">%1$ld user</cds-unit><cds-unit id=\"substitutions.arg1_iphone.plural.other\">%1$ld users</cds-unit></cds-root>
""",
                                                  deviceName: "mac")
        XCTAssertEqual(parseResult1, "Device has %1$ld users in %2$ld folders")

        let parseResult2 = XMLPluralParser.extract(pluralString: """
<cds-root><cds-unit id=\"device.iphone\">Device has %1$#@arg1_iphone@ in %2$ld folders</cds-unit><cds-unit id=\"device.other\">Device has %ld users in %ld folders</cds-unit><cds-unit id=\"substitutions.arg1_iphone.plural.one\">%1$ld user</cds-unit><cds-unit id=\"substitutions.arg1_iphone.plural.other\">%1$ld users</cds-unit></cds-root>
""",
                                                  deviceName: "iphone")
        let expectedResult2 = "Device has %1$#@{arg1_iphone, plural, one {%ld user} other {%ld users}}@ in %2$ld folders"
        XCTAssertEqual(parseResult2, expectedResult2)

        XCTAssertEqual(
            expectedResult2.extractICUPlurals(),
            [
                "{arg1_iphone, plural, one {%ld user} other {%ld users}}" : ICUPluralResult(
                                extractedPlurals: [
                                    .one: "%ld user",
                                    .other: "%ld users"
                                ])
            ]
        )
    }

    static var allTests = [
        ("testDuplicateLocaleFiltering", testDuplicateLocaleFiltering),
        ("testCurrentLocaleProvider", testCurrentLocaleProvider),
        ("testEncodingSourceStringMeta", testEncodingSourceStringMeta),
        ("testEncodingSourceString", testEncodingSourceString),
        ("testEncodingSourceStringWithMeta", testEncodingSourceStringWithMeta),
        ("testExtractMultipleICUPlurals", testExtractMultipleICUPlurals),
        ("testExtractICUPlurals", testExtractICUPlurals),
        ("testPlatformFormatMultiple", testPlatformFormatMultiple),
        ("testPlatformFormat", testPlatformFormat),
        ("testTXNativeFetchTranslationsWithStatus", testTXNativeFetchTranslationsWithStatus),
        ("testTXNativeFetchTranslationsWithTags", testTXNativeFetchTranslationsWithTags),
        ("testCDSHandlerFetchTranslationsWithStatus", testCDSHandlerFetchTranslationsWithStatus),
        ("testCDSHandlerFetchTranslationsWithTags", testCDSHandlerFetchTranslationsWithTags),
        ("testFetchTranslations", testFetchTranslations),
        ("testFetchTranslationsNotReady", testFetchTranslationsNotReady),
        ("testPushTranslations", testPushTranslations),
        ("testPushTranslationsNotReady", testPushTranslationsNotReady),
        ("testReplaceAllPolicy", testReplaceAllPolicy),
        ("testUpdateUsingTranslatePolicy", testUpdateUsingTranslatePolicy),
        ("testReadOnlyCache", testReadOnlyCache),
        ("testPlatformStrategyWithInvalidSourceString", testPlatformStrategyWithInvalidSourceString),
        ("testErrorPolicy", testErrorPolicy),
        ("testErrorPolicyException", testErrorPolicyException),
        ("testCurrentLocaleNotFirstPreference", testCurrentLocaleNotFirstPreference),
        ("testCurrentLocaleNotAnyPreference", testCurrentLocaleNotAnyPreference),
        ("testSourceLocalePosition", testSourceLocalePosition),
        ("testTranslateWithSourceStringsInCache", testTranslateWithSourceStringsInCache),
        ("testXMLPluralParserDeviceVariation", testXMLPluralParserDeviceVariation),
        ("testXMLPluralParserDeviceVariationiPadFallbackiPhone", testXMLPluralParserDeviceVariationiPadFallbackiPhone),
        ("testXMLPluralParserDeviceVariationiPadFallbackOther", testXMLPluralParserDeviceVariationiPadFallbackOther),
        ("testXMLPluralParserDevicePluralVariation", testXMLPluralParserDevicePluralVariation),
        ("testXMLPluralParserSimpleSubstitutions", testXMLPluralParserSimpleSubstitutions),
        ("testXMLPluralParserSimpleSubstitutionsStringsDict", testXMLPluralParserSimpleSubstitutionsStringsDict),
        ("testXMLPluralParserSimpleSubstitutionsStringsDictAlt", testXMLPluralParserSimpleSubstitutionsStringsDictAlt),
        ("testXMLPluralParserDeviceAndSubstitutions", testXMLPluralParserDeviceAndSubstitutions),
        ("testXMLDeviceSubstitutionSpecial", testXMLDeviceSubstitutionSpecial),
    ]
}
