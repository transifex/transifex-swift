//
//  CDSHandler.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 3/8/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Handles the logic of a pull HTTP request to CDS for a certain locale code
class CDSPullRequest {

    private static let MAX_RETRIES = 20;

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
        var data : LocaleStrings
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
                                                    LocaleStrings?,
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
            
            case 200:
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
                break
            case 202:
                if self.retryCount < CDSPullRequest.MAX_RETRIES {
                    self.retryCount += 1
                    self.perform(with: completionHandler)
                }
                else {
                    completionHandler(self.code,
                                      nil,
                                      .maxRetriesReached)
                }
                break
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
        self.session = session ?? URLSession(configuration: .ephemeral)
    }
    
    /// Fetch translations from CDS.
    ///
    /// - Parameters:
    ///   - localeCode: an optional locale to fetch translations from; if none provided it will fetch
    ///   translations for all locales defined in the configuration
    ///   - completionHandler: a callback function to call when the operation is complete
    public func fetchTranslations(localeCode: String? = nil,
                                  completionHandler: @escaping ([String: LocaleStrings]) -> Void) {
        guard let cdsHostURL = URL(string: cdsHost) else {
            print("Error: Invalid CDS host URL: \(cdsHost)")
            completionHandler([:])
            return
        }
        
        let baseURL = cdsHostURL.appendingPathComponent("content")
        
        var fetchLocaleCodes: [String]
        
        if let localeCode = localeCode {
            fetchLocaleCodes = [ localeCode ]
        }
        else {
            fetchLocaleCodes = localeCodes
        }
            
        var requestsByLocale : [String: URLRequest] = [:]

        for code in fetchLocaleCodes {
            let url = baseURL.appendingPathComponent(code)
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = getHeaders(withSecret: false)
            requestsByLocale[code] = request
        }

        var requestsFinished = 0
        var translationsByLocale: [String: LocaleStrings] = [:]

        for (code, requestByLocale) in requestsByLocale {
            let cdsRequest = CDSPullRequest(with: requestByLocale,
                                            code: code,
                                            session: self.session)
            cdsRequest.perform { (code, localeStrings, error) in
                requestsFinished += 1
                
                if let error = error {
                    print("Error fetching \(code): \(error)")
                }
                else {
                    translationsByLocale[code] = localeStrings
                }
                
                if requestsFinished == requestsByLocale.count {
                    completionHandler(translationsByLocale)
                }
            }
        }
    }
    
    /// Serialize the given source strings to a format suitable for the CDS.
    ///
    /// - Parameter strings: a list of `SourceString` objects
    /// - Returns: a JSON-friendly dictionary
    private func serializeSourceStrings(_ strings: [SourceString]) -> [String: String] {
        var sourceStrings: [String:String] = [:]
        for string in strings {
            do {
                let jsonData = try JSONEncoder().encode(string)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    sourceStrings[string.key] = jsonString
                }
            } catch {
                print("Error encoding source string \(string): \(error.localizedDescription)")
            }
        }
        return sourceStrings
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
