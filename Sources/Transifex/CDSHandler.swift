//
//  CDSHandler.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 3/8/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Completion handler used when fetching translations from CDS
public typealias TXPullCompletionHandler = (TXTranslations, [Error]) -> Void

/// Handles the logic of a pull HTTP request to CDS for a certain locale code
class CDSPullRequest {

    private static let MAX_RETRIES = 20

    let code : String
    let request : URLRequest
    let session : URLSession
    
    private var retryCount = 0
    
    enum RequestError: Error {
        case requestFailed(error : Error)
        case invalidHTTPResponse
        case serverError(statusCode : Int)
        case maxRetriesReached
        case nonParsableResponse
    }

    struct RequestData : Codable {
        var data: TXLocaleStrings
    }

    init(with request : URLRequest, code : String, session : URLSession) {
        self.code = code
        self.request = request
        self.session = session
    }
    
    /// Performs the request to CDS and offers a completion handler when the request succeeds or fails.
    ///
    /// - Parameter completionHandler: The completion handler that includes the locale code,
    /// the extracted LocaleStrings structure from the server response and the error object when the
    /// request fails
    func perform(with completionHandler: @escaping (String,
                                                    TXLocaleStrings?,
                                                    RequestError?) -> Void) {
        session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                completionHandler(self.code,
                                  nil,
                                  .requestFailed(error: error!))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completionHandler(self.code,
                                  nil,
                                  .invalidHTTPResponse)
                return
            }
            
            let statusCode = httpResponse.statusCode
            
            switch statusCode {
            
            case CDSHandler.HTTP_STATUS_CODE_OK:
                if let data = data {
                    let decoder = JSONDecoder()
                    
                    do {
                        let request = try decoder.decode(RequestData.self,
                                                         from: data)
                        completionHandler(self.code,
                                          request.data,
                                          nil)
                    }
                    catch {
                        completionHandler(self.code,
                                          nil,
                                          .requestFailed(error: error))
                    }
                }
                else {
                    completionHandler(self.code,
                                      nil,
                                      .nonParsableResponse)
                }
            case CDSHandler.HTTP_STATUS_CODE_ACCEPTED:
                Logger.info("Received 202 response while fetching locale: \(self.code)")
                
                if self.retryCount < CDSPullRequest.MAX_RETRIES {
                    self.retryCount += 1
                    self.perform(with: completionHandler)
                }
                else {
                    completionHandler(self.code,
                                      nil,
                                      .maxRetriesReached)
                }
            default:
                completionHandler(self.code,
                                  nil,
                                  .serverError(statusCode: statusCode))
            }
        }.resume()
    }
}

/// Handles communication with the Content Delivery Service.
class CDSHandler {

    private static let CDS_HOST = "https://cds.svc.transifex.net"
    
    private static let CONTENT_ENDPOINT = "content"
    private static let INVALIDATE_ENDPOINT = "invalidate"
    
    fileprivate static let HTTP_STATUS_CODE_OK = 200
    fileprivate static let HTTP_STATUS_CODE_ACCEPTED = 202
    fileprivate static let HTTP_STATUS_CODE_FORBIDDEN = 403
    
    /// Internal structure that's used to prepare the SourceStrings for the CDS push
    private struct PushData: Encodable {
        var data: [String:SourceString]
        struct Meta: Encodable {
            var purge: Bool
        }
        var meta: Meta
    }
    
    /// Private structure that's used to parse the data received by the invalidate endpoint
    private struct InvalidationResponseData: Decodable {
        var status: String
        var token: String
        var count: Int
    }
    
    /// Private structure that's used to parse the server response when pushing source strings
    private struct PushResponseData: Decodable {
        var created: Int
        var updated: Int
        var skipped: Int
        var deleted: Int
        var failed: Int
        var errors: [PushResponseError]
    }
    
    private struct PushResponseError: Decodable {
        var status: String
        var code: String
        var title: String
        var detail: String
        var source: [String: String]
    }

    /// A list of locale codes for the configured languages in the application
    let localeCodes: [String]
    
    /// The API token to use for connecting to the CDS
    let token: String
    
    /// The API secret to use for connecting to the CDS
    let secret: String?
    
    /// The host of the Content Delivery Service
    let cdsHost: String
    
    /// The url session to be used for the requests to the CDS, defaults to an ephemeral URLSession
    let session: URLSession
    
    /// An etag per locale code, used for optimizing requests
    var etagByLocale: [String: String] = [:]
    
    /// Constructor
    ///
    /// - Parameters:
    ///   - localeCodes: a list of locale codes for the configured languages in the application
    ///   - token: the API token to use for connecting to the CDS
    ///   - secret: the API secret to use for connecting to the CDS
    ///   - cdsHost: the host of the Content Delivery Service
    init(localeCodes: [String],
         token: String,
         secret: String? = nil,
         cdsHost: String? = CDS_HOST,
         session: URLSession? = nil) {
        self.localeCodes = localeCodes
        self.token = token
        self.secret = secret
        self.cdsHost = cdsHost ?? CDSHandler.CDS_HOST
        
        if let session = session {
            self.session = session
        }
        else {
            let sessionConfiguration: URLSessionConfiguration = .ephemeral
            sessionConfiguration.urlCache = nil
            
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }
    
    enum FetchError: Error {
        case invalidCDSURL
        case noLocaleCodes
    }
    
    /// Fetch translations from CDS.
    ///
    /// - Parameters:
    ///   - localeCode: an optional locale to fetch translations from; if none provided it will fetch
    ///   translations for all locales defined in the configuration
    ///   - completionHandler: a callback function to call when the operation is complete
    public func fetchTranslations(localeCode: String? = nil,
                                  completionHandler: @escaping TXPullCompletionHandler) {
        guard let cdsHostURL = URL(string: cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(cdsHost)")
            completionHandler([:], [FetchError.invalidCDSURL])
            return
        }
        
        let baseURL = cdsHostURL.appendingPathComponent(CDSHandler.CONTENT_ENDPOINT)
        
        var fetchLocaleCodes: [String]
        
        if let localeCode = localeCode {
            fetchLocaleCodes = [ localeCode ]
        }
        else {
            fetchLocaleCodes = localeCodes
        }
        
        if fetchLocaleCodes.count == 0 {
            Logger.error("Error: No locale codes to fetch")
            completionHandler([:], [FetchError.noLocaleCodes])
            return
        }
        
        Logger.verbose("Fetching translations from CDS: \(fetchLocaleCodes)...")
        
        var requestsByLocale : [String: URLRequest] = [:]

        for code in fetchLocaleCodes {
            let url = baseURL.appendingPathComponent(code)
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = getHeaders(withSecret: false)
            requestsByLocale[code] = request
        }

        var requestsFinished = 0
        var translationsByLocale: TXTranslations = [:]
        var errors: [Error] = []
        
        for (code, requestByLocale) in requestsByLocale {
            let cdsRequest = CDSPullRequest(with: requestByLocale,
                                            code: code,
                                            session: self.session)
            cdsRequest.perform { (code, localeStrings, error) in
                requestsFinished += 1
                
                if let error = error {
                    errors.append(error)
                }
                else {
                    translationsByLocale[code] = localeStrings
                }
                
                if requestsFinished == requestsByLocale.count {
                    completionHandler(translationsByLocale, errors)
                }
            }
        }
    }
    
    /// Performs a cache invalidation for all project languages on CDS
    ///
    /// - Parameter completionHandler: A completion handler informing the caller whether the
    /// request was successful or not
    public func forceCacheInvalidation(completionHandler: @escaping (Bool) -> Void) {
        guard let cdsHostURL = URL(string: cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(cdsHost)")
            completionHandler(false)
            return
        }
        
        Logger.verbose("Invalidating CDS cache...")
        
        let baseURL = cdsHostURL.appendingPathComponent(CDSHandler.INVALIDATE_ENDPOINT)
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = getHeaders(withSecret: true)

        session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                Logger.error("Error invalidating CDS cache: \(error!)")
                completionHandler(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Error invalidating CDS cache: Not a valid HTTP response")
                completionHandler(false)
                return
            }
            
            guard httpResponse.statusCode == CDSHandler.HTTP_STATUS_CODE_OK else {
                Logger.error("HTTP Status error while invalidating CDS cache: \(httpResponse.statusCode)")
                completionHandler(false)
                return
            }
            
            guard let data = data else {
                Logger.error("No data received while invalidating CDS cache")
                completionHandler(false)
                return
            }
            
            let decoder = JSONDecoder()
            
            do {
                let response = try decoder.decode(InvalidationResponseData.self,
                                                  from: data)
                
                if response.status != "success" {
                    Logger.error("Unsuccessful invalidation request")
                    completionHandler(false)
                    return
                }
                
                Logger.verbose("Invalidated \(response.count) translations from CDS for all locales in the project")
                completionHandler(true)
            }
            catch {
                Logger.error("Error while decoding CDS invalidation response: \(error)")
                completionHandler(false)
            }
        }.resume()
    }
    
    /// Pushes translations to CDS.
    ///
    /// - Parameters:
    ///   - translations: A list of `TXSourceString` objects
    ///   - purge: Whether the request will replace the entire resource content (true) or not (false)
    ///   Defaults to false
    ///   - completionHandler: a callback function to call when the operation is complete
    public func pushTranslations(_ translations: [TXSourceString],
                                 purge: Bool = false,
                                 completionHandler: @escaping (Bool) -> Void) {
        guard let cdsHostURL = URL(string: cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(cdsHost)")
            completionHandler(false)
            return
        }
        
        guard let jsonData = serializeTranslations(translations,
                                                   purge: purge) else {
            Logger.error("Error while serializing translations")
            completionHandler(false)
            return
        }
        
        Logger.verbose("Pushing translations to CDS: \(translations)...")
        
        let baseURL = cdsHostURL.appendingPathComponent(CDSHandler.CONTENT_ENDPOINT)
        var request = URLRequest(url: baseURL)
        request.httpBody = jsonData
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = getHeaders(withSecret: true)

        session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                Logger.error("Error pushing strings: \(error!)")
                completionHandler(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Error pushing strings: Not a valid HTTP response")
                completionHandler(false)
                return
            }
            
            let statusCode = httpResponse.statusCode

            if statusCode == CDSHandler.HTTP_STATUS_CODE_OK {
                completionHandler(true)
                return
            }
            
            Logger.error("HTTP Status error while pushing strings: \(statusCode)")
            
            if statusCode == CDSHandler.HTTP_STATUS_CODE_FORBIDDEN {
                completionHandler(false)
                return
            }
            
            guard let data = data else {
                completionHandler(false)
                return
            }
            
            let decoder = JSONDecoder()
            var response : PushResponseData? = nil
            
            do {
                response = try decoder.decode(PushResponseData.self,
                                              from: data)
            }
            catch {
                Logger.error("Error while decoding CDS push response: \(error)")
            }
            
            if let response = response {
                for error in response.errors {
                    Logger.error("""
\(error.title) (\(error.status) - \(error.code)):
\(error.detail)
Source:
\(error.source)
""")
                }
            }

            completionHandler(false)
        }.resume()
    }
    
    /// Serialize the given translation units to the final data that should be passed in the push CDS request.
    ///
    /// - Parameter translations: a list of `TXSourceString` objects
    /// - Parameter purge: Whether the resulting data will replace the entire resource content or not
    /// - Returns: a Data object ready to be used in the CDS request
    private func serializeTranslations(_ translations: [TXSourceString],
                                       purge: Bool = false) -> Data? {
        var sourceStrings: [String:SourceString] = [:]
        
        for translation in translations {
            sourceStrings[translation.key] = translation.sourceStringRepresentation()
        }
        
        let data = PushData(data: sourceStrings,
                            meta: PushData.Meta(purge: purge))
        
        var jsonData: Data?
        
        do {
            jsonData = try JSONEncoder().encode(data)
        }
        catch {
            Logger.error("Error encoding source strings: \(error)")
        }
        
        return jsonData
    }

    /// Return the headers to use when making requests.
    ///
    /// - Parameters:
    ///   - withSecret: if true, the Bearer authorization header will also include the secret, otherise it
    ///   will only use the token
    ///   - etag: an optional etag to include for optimization
    /// - Returns: a dictionary with all headers
    private func getHeaders(withSecret: Bool = false,
                            etag: String? = nil) -> [String: String] {
        var headers = [
            "Accept-Encoding": "gzip",
            "Content-Type": "application/json",
            "X-NATIVE-SDK": "mobile/ios/\(TXNative.version)"
        ]
        if withSecret == true,
           let secret = secret {
            headers["Authorization"] = "Bearer \(token):\(secret)"
        }
        else {
            headers["Authorization"] = "Bearer \(token)"
        }
        if let etag = etag {
            headers["If-None-Match"] = etag
        }
        return headers
    }
}
