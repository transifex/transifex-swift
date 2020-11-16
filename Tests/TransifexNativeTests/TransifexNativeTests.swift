import XCTest
@testable import TransifexNative

/// Partially mocked URLSessionDataTask and URLSession classes so that we can test how
/// TransifexNative behaves on certain server responses.
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
        if let mockResponse = mockResponses?[mockResponseIndex] {
            
            mockResponseIndex += 1
            
            let data = mockResponse.data
            let error = mockResponse.error
            let statusCode = mockResponse.statusCode
            
            return URLSessionDataTaskMock {
                let response = HTTPURLResponse(url: request.url!,
                                               statusCode: statusCode ?? 200,
                                               httpVersion: nil,
                                               headerFields: nil)
                completionHandler(data, response, error)
            }
        }
        else {
            return URLSessionDataTaskMock {
                completionHandler(nil, nil, nil)
            }
        }
    }
}

class MockLocaleProvider : CurrentLocaleProvider {
    private var mockLocaleCode : String
    
    init(_ mockLocaleCode: String) {
        self.mockLocaleCode = mockLocaleCode
    }
    
    func currentLocale() -> String {
        return self.mockLocaleCode
    }
}

final class TransifexNativeTests: XCTestCase {
    func testDuplicateLocaleFiltering() {
        let duplicateLocales = [ "en", "fr", "en" ]
        
        let localeState = LocaleState(sourceLocale: "en",
                                      appLocales: duplicateLocales)
        
        let expectedAppLocales = [ "en", "fr" ]
        
        // We test the sorted arrays, in case the `LocaleState` initializer
        // has resorted the passed array.
        XCTAssertEqual(localeState.appLocales.sorted(),
                       expectedAppLocales.sorted())
    }
    
    func testCurrentLocaleProvider() {
        let mockCode = "mock_code"
        let mockLocaleProvider = MockLocaleProvider(mockCode)
        let localeState = LocaleState(sourceLocale: nil,
                                      appLocales: [],
                                      currentLocaleProvider: mockLocaleProvider)
        
        XCTAssertEqual(localeState.currentLocale, mockCode)
    }
    
    func testEncodingSourceStringMeta() {
        let sourceStringMeta = SourceStringMeta(context: ["test"],
                                                comment: "Test comment",
                                                characterLimit: 10,
                                                tags: ["test"])
        
        let jsonData = try! JSONEncoder().encode(sourceStringMeta)
        let jsonString = String(data: jsonData, encoding: .utf8)
        
        let expectedJsonString = "{\"character_limit\":10,\"tags\":[\"test\"],\"developer_comment\":\"Test comment\",\"context\":[\"test\"]}"
        
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

        let jsonData = try! JSONEncoder().encode(sourceString)
        let jsonString = String(data: jsonData, encoding: .utf8)

        let expectedJsonString = "{\"string\":\"test string\",\"meta\":{\"character_limit\":10,\"tags\":[\"test\"],\"developer_comment\":\"Test comment\",\"context\":[\"test\"]}}"
        
        XCTAssertEqual(jsonString, expectedJsonString)
    }
    
    func testFetchTranslations() {
        let expectation = self.expectation(description: "Waiting for translations to be fetched")
        var translationsResult : [String: LocaleStrings]? = nil
        
        let mockResponseData = "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8)
        
        let mockResponse = MockResponse(data: mockResponseData,
                                        statusCode: 200,
                                        error: nil)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [mockResponse]
        
        let cdsHandler = CDSHandler(localeCodes: [ "en" ],
                                    token: "test_token",
                                    session: urlSession)
        
        cdsHandler.fetchTranslations { (translations) in
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
        var translationsResult : [String: LocaleStrings]? = nil
        
        let mockResponseData = "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8)
        
        let mockResponseNotReady = MockResponse(data: nil,
                                                statusCode: 202,
                                                error: nil)
        let mockResponseReady = MockResponse(data: mockResponseData,
                                             statusCode: 200,
                                             error: nil)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [
            mockResponseNotReady,
            mockResponseNotReady,
            mockResponseReady
        ]
        
        let cdsHandler = CDSHandler(localeCodes: [ "en" ],
                                    token: "test_token",
                                    session: urlSession)
        
        cdsHandler.fetchTranslations { (translations) in
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

    static var allTests = [
        ("testDuplicateLocaleFiltering", testDuplicateLocaleFiltering),
        ("testCurrentLocaleProvider", testCurrentLocaleProvider),
        ("testEncodingSourceStringMeta", testEncodingSourceStringMeta),
        ("testEncodingSourceString", testEncodingSourceString),
        ("testEncodingSourceStringWithMeta", testEncodingSourceStringWithMeta),
        ("testFetchTranslations", testFetchTranslations),
        ("testFetchTranslationsNotReady", testFetchTranslationsNotReady),
    ]
}
