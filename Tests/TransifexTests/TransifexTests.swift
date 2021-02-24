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
        // For POST requests, return 200 if the data included in the
        // mock response is equal to the data of the HTTP body of the
        // request.
        if request.httpMethod == "POST",
           let mockResponse = mockResponses?[mockResponseIndex] {
            mockResponseIndex += 1
            
            return URLSessionDataTaskMock {
                if mockResponse.data == request.httpBody {
                    let response = HTTPURLResponse(url: request.url!,
                                                   statusCode: 200,
                                                   httpVersion: nil,
                                                   headerFields: nil)
                    completionHandler(nil, response, nil)
                }
                else {
                    let response = HTTPURLResponse(url: request.url!,
                                                   statusCode: 403,
                                                   httpVersion: nil,
                                                   headerFields: nil)
                    completionHandler(nil, response, nil)
                }
            }
        }
        else if let mockResponse = mockResponses?[mockResponseIndex] {
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
             params: [String : Any]) -> String {
        return "ERROR"
    }
}

final class TransifexTests: XCTestCase {
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
    
    func testExtractICUPlurals() {
        XCTAssertEqual(
            "{???, plural, one {One table} two {A couple of tables} other {%d tables}}".extractICUPlurals(),
            [
                PluralizationRule.one: "One table",
                PluralizationRule.two: "A couple of tables",
                PluralizationRule.other: "%d tables"
            ]
        )
        XCTAssertEqual(
            "{cnt, plural, other {%d tables}}".extractICUPlurals(),
            [PluralizationRule.other: "%d tables"]
        )
        XCTAssertEqual("{cnt, plural, }".extractICUPlurals(), [:])
        XCTAssertEqual("{something}".extractICUPlurals(), nil)
    }
    
    func testFetchTranslations() {
        let expectation = self.expectation(description: "Waiting for translations to be fetched")
        var translationsResult : TXTranslations? = nil
        
        let mockResponseData = "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8)
        
        let mockResponse = MockResponse(data: mockResponseData,
                                        statusCode: 200,
                                        error: nil)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [mockResponse]
        
        let cdsHandler = CDSHandler(localeCodes: [ "en" ],
                                    token: "test_token",
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
        
        let expectedDataString = "{\"meta\":{\"purge\":false},\"data\":{\"testkey\":{\"string\":\"sourceString\",\"meta\":{\"character_limit\":0,\"occurrences\":[]}}}}"
        
        let mockResponse = MockResponse(data: expectedDataString.data(using: .utf8))
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [ mockResponse ]
        let cdsHandler = CDSHandler(localeCodes: [ "en" ],
                                    token: "test_token",
                                    session: urlSession)
        
        var pushResult : Bool = false
        cdsHandler.pushTranslations(translations) { (result) in
            pushResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertTrue(pushResult)
        }
    }
    
    func testOverrideFilterCacheAll() {
        let firstProviderTranslations: TXTranslations = [
            "en": [
                "key1": [ "string": "localized string 1" ]
            ]
        ]
        let secondProviderTranslations: TXTranslations = [
            "en": [
                "key2": [ "string": "localized string 2" ],
                "key3": [ "string": "" ]
            ]
        ]
        
        let firstProvider = MockCacheProvider(translations: firstProviderTranslations)
        let secondProvider = MockCacheProvider(translations: secondProviderTranslations)
        
        let cache = TXProviderBasedCache(
            providers: [
                firstProvider,
                secondProvider
            ],
            internalCache: TXStringOverrideFilterCache(
                policy: .overrideAll,
                internalCache: TXMemoryCache()
            )
        )
        
        XCTAssertNil(cache.get(key: "key1", localeCode: "en"))
        XCTAssertNotNil(cache.get(key: "key2", localeCode: "en"))
        XCTAssertNil(cache.get(key: "key3", localeCode: "en"))
    }
    
    func testOverrideFilterCacheUntranslated() {
        let firstProviderTranslations: TXTranslations = [
            "en": [
                "key1": [ "string": "localized string 1" ]
            ]
        ]
        let secondProviderTranslations: TXTranslations = [
            "en": [
                "key2": [ "string": "localized string 2" ],
                "key3": [ "string": "" ]
            ]
        ]
        
        let firstProvider = MockCacheProvider(translations: firstProviderTranslations)
        let secondProvider = MockCacheProvider(translations: secondProviderTranslations)
        
        let memoryCache =  TXMemoryCache()
        memoryCache.update(translations: [
            "en": [
                "key1": [ "string": "old localized string 1"]
            ]
        ])
        
        let cache = TXProviderBasedCache(
            providers: [
                firstProvider,
                secondProvider
            ],
            internalCache: TXStringOverrideFilterCache(
                policy: .overrideUntranslatedOnly,
                internalCache: memoryCache
            )
        )
        
        XCTAssertNotNil(cache.get(key: "key1", localeCode: "en"))
        XCTAssertTrue(cache.get(key: "key1", localeCode: "en") == "old localized string 1")
        XCTAssertNotNil(cache.get(key: "key2", localeCode: "en"))
        XCTAssertNil(cache.get(key: "key3", localeCode: "en"))
    }
    
    func testOverrideFilterCacheTranslated() {
        let firstProviderTranslations: TXTranslations = [
            "en": [
                "key1": [ "string": "localized string 1" ]
            ]
        ]
        let secondProviderTranslations: TXTranslations = [
            "en": [
                "key2": [ "string": "localized string 2" ]
            ]
        ]
        
        let firstProvider = MockCacheProvider(translations: firstProviderTranslations)
        let secondProvider = MockCacheProvider(translations: secondProviderTranslations)
        
        let memoryCache =  TXMemoryCache()
        memoryCache.update(translations: [
            "en": [
                "key1": [ "string": "old localized string 1"]
            ]
        ])
        
        let cache = TXProviderBasedCache(
            providers: [
                firstProvider,
                secondProvider
            ],
            internalCache: TXStringOverrideFilterCache(
                policy: .overrideUsingTranslatedOnly,
                internalCache: memoryCache
            )
        )
        
        XCTAssertNotNil(cache.get(key: "key1", localeCode: "en"))
        XCTAssertTrue(cache.get(key: "key1", localeCode: "en") == "localized string 1")
        XCTAssertNotNil(cache.get(key: "key2", localeCode: "en"))
    }
    
    func testPlatformStrategyWithInvalidSourceString() {
        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["fr"])
        
        TXNative.initialize(locales: localeState,
                            token: "<token>",
                            secret: "<secret>")
        
        let core = NativeCore(locales: localeState,
                              token: "<token>",
                              secret: "<secret>",
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
                            token: "<token>",
                            secret: "<secret>",
                            errorPolicy: MockErrorPolicy(),
                            renderingStrategy: .icu)
        
        let result = TXNative.translate(sourceString: "source string", params: [:], context: nil)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, "ERROR")
    }

    func testCurrentLocale() {
        let appleLanguagesKey = "AppleLanguages"
        let storedLanguages = UserDefaults.standard.value(forKey: appleLanguagesKey)
        
        UserDefaults.standard.set([ "el" ],
                                  forKey: appleLanguagesKey)
        
        let locale = TXLocaleState(appLocales: [])
        
        XCTAssertEqual(locale.currentLocale,
                       "el")
        
        UserDefaults.standard.set(storedLanguages,
                                  forKey: appleLanguagesKey)
    }
    
    static var allTests = [
        ("testDuplicateLocaleFiltering", testDuplicateLocaleFiltering),
        ("testCurrentLocaleProvider", testCurrentLocaleProvider),
        ("testEncodingSourceStringMeta", testEncodingSourceStringMeta),
        ("testEncodingSourceString", testEncodingSourceString),
        ("testEncodingSourceStringWithMeta", testEncodingSourceStringWithMeta),
        ("testFetchTranslations", testFetchTranslations),
        ("testFetchTranslationsNotReady", testFetchTranslationsNotReady),
        ("testExtractICUPlurals", testExtractICUPlurals),
        ("testPushTranslations", testPushTranslations),
        ("testOverrideFilterCacheAll", testOverrideFilterCacheAll),
        ("testOverrideFilterCacheUntranslated", testOverrideFilterCacheUntranslated),
        ("testOverrideFilterCacheTranslated", testOverrideFilterCacheTranslated),
        ("testPlatformStrategyWithInvalidSourceString", testPlatformStrategyWithInvalidSourceString),
        ("testErrorPolicy", testErrorPolicy),
        ("testCurrentLocale", testCurrentLocale),
    ]
}
