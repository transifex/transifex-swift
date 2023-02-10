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

/// All possible errors that may be produced during a fetch (pull) or a push operation
public enum TXCDSError: Error {
    /// The provided CDS url was invalid
    case invalidCDSURL
    /// No locale codes were provided to the fetch operation
    case noLocaleCodes
    /// Translation strings to be pushed failed to be serialized
    case failedSerialization
    /// The CDS request failed with a specific underlying error
    case requestFailed(error : Error)
    /// The HTTP response received by CDS was invalid
    case invalidHTTPResponse
    /// The server responded with a specific failure status code
    case serverError(statusCode : Int)
    /// The fetch / push operation exceeded the MAX_RETRIES (20)
    case maxRetriesReached
    /// The server response could not be parsed
    case nonParsableResponse
    /// No data was received from the server response
    case noData
    /// The job status request failed
    case failedJobRequest
    /// A specific job error was returned by CDS
    case jobError(status: String, code: String, title: String,
                  detail: String, source: [String : String])
}

/// Handles the logic of a pull HTTP request to CDS for a certain locale code
class CDSPullRequest {
    let code : String
    let request : URLRequest
    let session : URLSession
    
    private var retryCount = 0
    
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
                                                    TXCDSError?) -> Void) {
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
                
                if self.retryCount < CDSHandler.MAX_RETRIES {
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

/// The struct used to configure the communication with CDS, passed into the CDSHander initializer.
struct CDSConfiguration {
    /// A list of locale codes for the configured languages in the application
    var localeCodes: [String]
    /// The API token to use for connecting to the CDS
    var token: String
    /// The API secret to use for connecting to the CDS
    var secret: String? = nil
    /// The host of the Content Delivery Service
    var cdsHost: String = CDSHandler.CDS_HOST
    /// Fetch only strings that contain specific tags from CDS, e.g. "master,react"
    var filterTags: [String] = []
    /// Fetch only strings matching translation status: reviewed,proofread,finalized
    var filterStatus: String? = nil
}

/// Handles communication with the Content Delivery Service.
class CDSHandler {
    /// Max retries for both the pull and the push / job status requests
    fileprivate static let MAX_RETRIES = 20

    internal static let CDS_HOST = "https://cds.svc.transifex.net"
    
    private static let CONTENT_ENDPOINT = "content"
    private static let INVALIDATE_ENDPOINT = "invalidate"
    
    private static let FILTER_TAGS_PARAM = "filter[tags]"
    private static let FILTER_STATUS_PARAM = "filter[status]"
    
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
        struct Data: Decodable {
            var status: String
            var token: String
            var count: Int
        }
        var data: Data
    }
    
    /// Private structure that's used to parse the server response when pushing source strings
    private struct PushResponseData: Decodable {
        struct Links: Decodable {
            var job: String
        }
        struct Data: Decodable {
            var id: String
            var links: Links
        }
        var data: Data
    }
    
    /// Private structure that's used to parse the server response when fetching the job status.
    ///
    /// The errors field is available only in the 'completed' and 'failed' statuses and the details field is
    /// available only in the 'completed' status.
    private struct JobStatusResponseData: Decodable {
        struct Data: Decodable {
            var status: JobStatus
            var errors: [JobError]?
            var details: JobDetails?
        }
        var data: Data
    }
    
    private struct JobDetails: Decodable {
        var created: Int
        var updated: Int
        var skipped: Int
        var deleted: Int
        var failed: Int
    }
    
    private struct JobError: Decodable {
        var status: String
        var code: String
        var title: String
        var detail: String
        var source: [String: String]
    }
    
    private enum JobStatus: String, Decodable {
        case pending
        case processing
        case completed
        case failed
    }
    
    /// The url session to be used for the requests to the CDS, defaults to an ephemeral URLSession with
    /// a disabled URL cache.
    let session: URLSession
    
    /// The configuration structure holding all the neccessary settings for configuring the communication
    /// with CDS.
    let configuration: CDSConfiguration
    
    /// Constructor
    ///
    /// - Parameters:
    ///   - configuration: The configuration struct for communicating with CDS.
    ///   - session: The url session to be used for requests to CDS.
    init(configuration: CDSConfiguration,
         session: URLSession? = nil) {
        self.configuration = configuration
        
        if let session = session {
            self.session = session
        }
        else {
            let sessionConfiguration: URLSessionConfiguration = .ephemeral
            sessionConfiguration.urlCache = nil
            
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }
    
    /// Fetch translations from CDS.
    ///
    /// - Parameters:
    ///   - localeCode: an optional locale to fetch translations from; if none provided it will fetch
    ///   translations for all locales defined in the configuration
    ///   - tags: An optional list of tags so that only strings that have all of the given tags are fetched.
    ///   - status: An optional status so that only strings matching translation status are fetched.
    ///   - completionHandler: a callback function to call when the operation is complete
    public func fetchTranslations(localeCode: String? = nil,
                                  tags: [String] = [],
                                  status: String? = nil,
                                  completionHandler: @escaping TXPullCompletionHandler) {
        guard let cdsHostURL = URL(string: configuration.cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(configuration.cdsHost)")
            completionHandler([:], [TXCDSError.invalidCDSURL])
            return
        }
        
        let baseURL = cdsHostURL.appendingPathComponent(CDSHandler.CONTENT_ENDPOINT)
        
        var fetchLocaleCodes: [String]
        
        if let localeCode = localeCode {
            fetchLocaleCodes = [ localeCode ]
        }
        else {
            fetchLocaleCodes = configuration.localeCodes
        }
        
        if fetchLocaleCodes.count == 0 {
            Logger.error("Error: No locale codes to fetch")
            completionHandler([:], [TXCDSError.noLocaleCodes])
            return
        }
        
        Logger.verbose("Fetching translations from CDS: \(fetchLocaleCodes)...")
        
        var requestsByLocale : [String: URLRequest] = [:]

        for code in fetchLocaleCodes {
            let url = baseURL.appendingPathComponent(code)
            var request = buildURLRequest(url: url,
                                          tags: tags.count > 0 ? tags : configuration.filterTags,
                                          status: status ?? configuration.filterStatus)
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
        guard let cdsHostURL = URL(string: configuration.cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(configuration.cdsHost)")
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
                
                if response.data.status != "success" {
                    Logger.error("Unsuccessful invalidation request")
                    completionHandler(false)
                    return
                }
                
                Logger.verbose("Invalidated \(response.data.count) translations from CDS for all locales in the project")
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
                                 completionHandler: @escaping (Bool, [Error]) -> Void) {
        guard let cdsHostURL = URL(string: configuration.cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(configuration.cdsHost)")
            completionHandler(false,
                              [TXCDSError.invalidCDSURL])
            return
        }
        
        guard let jsonData = serializeTranslations(translations,
                                                   purge: purge) else {
            Logger.error("Error while serializing translations")
            completionHandler(false,
                              [TXCDSError.failedSerialization])
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
                completionHandler(false,
                                  [TXCDSError.requestFailed(error: error!)])
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Error pushing strings: Not a valid HTTP response")
                completionHandler(false,
                                  [TXCDSError.invalidHTTPResponse])
                return
            }
            
            if httpResponse.statusCode != CDSHandler.HTTP_STATUS_CODE_ACCEPTED {
                Logger.error("HTTP Status error while pushing strings: \(httpResponse.statusCode)")
                completionHandler(false,
                                  [TXCDSError.serverError(statusCode: httpResponse.statusCode)])
                return
            }
            
            guard let data = data else {
                Logger.error("Error: No data received while pushing strings")
                completionHandler(false,
                                  [TXCDSError.noData])
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
            
            guard let finalResponse = response else {
                completionHandler(false,
                                  [TXCDSError.nonParsableResponse])
                return
            }
            
            self.pollJobStatus(jobURL: finalResponse.data.links.job,
                               retryCount: 0,
                               completionHandler: completionHandler)
            
        }.resume()
    }
    
    /// Polls the job status for CDSHandler.MAX_RETRIES times, or until it receives a failure or a
    /// successful job status.
    ///
    /// Warning: Do not call this method from the main thread as it sleeps for 1 second before performing
    /// the actual network request.
    ///
    /// - Parameters:
    ///   - jobURL: The relative job url (e.g. /jobs/content/123)
    ///   - retryCount: The current retry number
    ///   - completionHandler: The completion handler that informs the caller whether the job was
    /// successful or not.
    private func pollJobStatus(jobURL: String,
                               retryCount: Int,
                               completionHandler: @escaping (Bool, [Error]) -> Void) {
        // Delay the job status request by 1 second, so that the server can
        // have enough time to process the job.
        Thread.sleep(forTimeInterval: 1.0)
        
        fetchJobStatus(jobURL: jobURL) {
            jobStatus, jobErrors, jobDetails in
            guard let finalJobStatus = jobStatus else {
                Logger.error("Error: Fetch job status request failed")
                completionHandler(false,
                                  [TXCDSError.failedJobRequest])
                return
            }
            
            var finalErrors: [Error] = []
            
            if let errors = jobErrors {
                for error in errors {
                    Logger.error("""
\(error.title) (\(error.status) - \(error.code)):
\(error.detail)
Source:
\(error.source)
""")
                    finalErrors.append(TXCDSError.jobError(status: error.status,
                                                           code: error.code,
                                                           title: error.title,
                                                           detail: error.detail,
                                                           source: error.source))
                }
            }
            
            if let details = jobDetails {
                Logger.verbose("""
created: \(details.created)
updated: \(details.updated)
skipped: \(details.skipped)
deleted: \(details.deleted)
failed: \(details.failed)
""")
            }
        
            switch finalJobStatus {
                case .pending:
                    fallthrough
                case .processing:
                    if retryCount < CDSHandler.MAX_RETRIES {
                        self.pollJobStatus(jobURL: jobURL,
                                           retryCount: retryCount + 1,
                                           completionHandler: completionHandler)
                    }
                    else {
                        completionHandler(false, [TXCDSError.maxRetriesReached])
                    }
                case .failed:
                    completionHandler(false, finalErrors)
                case .completed:
                    completionHandler(true, finalErrors)
            }
        }
    }
    
    /// Peforms a single job status request to the CDS for a given job id and returns the response
    /// asynchronously
    ///
    /// - Parameters:
    ///   - jobURL: The relative job url (e.g. /jobs/content/123)
    ///   - completionHandler: A completion handler that contains the parsed response. The
    ///   response consists of the job status (which is nil in case of a failure), an optional array of errors
    ///   in case job failed or succeeded with errros and an optional structure of the job details in case job
    ///   was successful.
    private func fetchJobStatus(jobURL: String,
                                completionHandler: @escaping (JobStatus?,
                                                              [JobError]?,
                                                              JobDetails?) -> Void) {
        guard let cdsHostURL = URL(string: configuration.cdsHost) else {
            Logger.error("Error: Invalid CDS host URL: \(configuration.cdsHost)")
            completionHandler(nil, nil, nil)
            return
        }
        
        Logger.verbose("Fetching job status for job: \(jobURL)...")
        
        let baseURL = cdsHostURL
            .appendingPathComponent(jobURL)
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = getHeaders(withSecret: true)

        session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                Logger.error("Error retrieving job status: \(error!)")
                completionHandler(nil, nil, nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Error retrieving job status: Not a valid HTTP response")
                completionHandler(nil, nil, nil)
                return
            }
            
            if httpResponse.statusCode != CDSHandler.HTTP_STATUS_CODE_OK {
                Logger.error("HTTP Status error while retrieving job status: \(httpResponse.statusCode)")
                completionHandler(nil, nil, nil)
                return
            }
            
            guard let finalData = data else {
                Logger.error("Error: No data received while retrieving job status")
                completionHandler(nil, nil, nil)
                return
            }
            
            let decoder = JSONDecoder()
            var responseData: JobStatusResponseData? = nil
            
            do {
                responseData = try decoder.decode(JobStatusResponseData.self,
                                                  from: finalData)
            }
            catch {
                Logger.error("Error while decoding CDS job status response: \(error)")
            }
            
            completionHandler(responseData?.data.status,
                              responseData?.data.errors,
                              responseData?.data.details)
            
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
            "Content-Type": "application/json; charset=utf-8",
            "X-NATIVE-SDK": "mobile/ios/\(TXNative.version)",
            "Accept-version": "v2"
        ]
        if withSecret == true,
           let secret = configuration.secret {
            headers["Authorization"] = "Bearer \(configuration.token):\(secret)"
        }
        else {
            headers["Authorization"] = "Bearer \(configuration.token)"
        }
        if let etag = etag {
            headers["If-None-Match"] = etag
        }
        return headers
    }
    
    /// Builds the URL request that is going to be used to query CDS using the optional tags list and status
    /// filters.
    ///
    /// - Parameters:
    ///   - url: The initial URL
    ///   - tags: The optional tag list filter
    ///   - status: The optional status filter
    /// - Returns: The final URL request to be used to query CDS
    private func buildURLRequest(url: URL,
                                 tags: [String],
                                 status: String?) -> URLRequest {
        guard tags.count > 0 || status != nil else {
            return URLRequest(url: url)
        }
        guard var components = URLComponents(url: url,
                                             resolvingAgainstBaseURL: false) else {
            return URLRequest(url: url)
        }
        var queryItems : [URLQueryItem] = []
        if tags.count > 0 {
            let tagList = tags.joined(separator: ",")
            let queryItem = URLQueryItem(name: Self.FILTER_TAGS_PARAM,
                                         value: tagList)
            queryItems.append(queryItem)
        }
        if let status = status {
            let queryItem = URLQueryItem(name: Self.FILTER_STATUS_PARAM,
                                         value: status)
            queryItems.append(queryItem)
        }
        components.queryItems = queryItems
        guard let tagRequestURL = components.url else {
            return URLRequest(url: url)
        }
        
        return URLRequest(url: tagRequestURL)
    }
}
