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
    var url : URL?
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
            
            let requestURL = request.url!
            let data = mockResponse.data
            let error = mockResponse.error
            let statusCode = mockResponse.statusCode
            let url = mockResponse.url
            
            var finalStatusCode = 200
            
            if let statusCode = statusCode {
                finalStatusCode = statusCode
            }
            else if let url = url {
                finalStatusCode = (url == requestURL ? 200 : 403)
            }
            
            return URLSessionDataTaskMock {
                let response = HTTPURLResponse(url: requestURL,
                                               statusCode: finalStatusCode,
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
    
    func testFetchTranslationsWithTags() {
        let expectation = self.expectation(description: "Waiting for translations to be fetched")
        var translationErrors : [Error]? = nil
        let mockResponseData = "{\"data\":{\"testkey1\":{\"string\":\"test string 1\"},\"testkey2\":{\"string\":\"test string 2\"}}}".data(using: .utf8)
        
        let expectedURL = URL(string: "https://cds.svc.transifex.net/content/en?filter%5Btags%5D=ios")
        let mockResponse = MockResponse(data: mockResponseData,
                                        url: expectedURL)
        
        let urlSession = URLSessionMock()
        urlSession.mockResponses = [mockResponse]
        
        let cdsHandler = CDSHandler(localeCodes: [ "en" ],
                                    token: "test_token",
                                    session: urlSession)
        
        cdsHandler.fetchTranslations(tags: ["ios"]) { translations, errors in
            translationErrors = errors
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { (error) in
            XCTAssertNil(error)
            XCTAssertNotNil(translationErrors)
            XCTAssertTrue(translationErrors?.count == 0)
        }
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
        XCTAssertEqual(result, "MOCKERROR")
    }
    
    func testErrorPolicyException() {
        let localeState = TXLocaleState(sourceLocale: "en",
                                        appLocales: ["fr"])
        
        TXNative.initialize(locales: localeState,
                            token: "<token>",
                            secret: "<secret>",
                            errorPolicy: MockErrorPolicyException(),
                            renderingStrategy: .icu)
        
        let result = TXNative.translate(sourceString: "source string", params: [:], context: nil)

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
                            token: "<token>",
                            secret: "<secret>",
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
    
    static var allTests = [
        ("testDuplicateLocaleFiltering", testDuplicateLocaleFiltering),
        ("testCurrentLocaleProvider", testCurrentLocaleProvider),
        ("testEncodingSourceStringMeta", testEncodingSourceStringMeta),
        ("testEncodingSourceString", testEncodingSourceString),
        ("testEncodingSourceStringWithMeta", testEncodingSourceStringWithMeta),
        ("testExtractICUPlurals", testExtractICUPlurals),
        ("testFetchTranslations", testFetchTranslations),
        ("testFetchTranslationsNotReady", testFetchTranslationsNotReady),
        ("testPushTranslations", testPushTranslations),
        ("testReplaceAllPolicy", testReplaceAllPolicy),
        ("testUpdateUsingTranslatePolicy", testUpdateUsingTranslatePolicy),
        ("testReadOnlyCache", testReadOnlyCache),
        ("testPlatformStrategyWithInvalidSourceString", testPlatformStrategyWithInvalidSourceString),
        ("testErrorPolicy", testErrorPolicy),
        ("testCurrentLocale", testCurrentLocale),
        ("testTranslateWithSourceStringsInCache", testTranslateWithSourceStringsInCache),
    ]
}
