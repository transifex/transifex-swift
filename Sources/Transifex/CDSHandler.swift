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
public enum TXCDSError: Error, CustomStringConvertible {
    case invalidCDSURL
    case noLocaleCodes
    case failedSerialization(error: Error)
    case requestFailed(error : Error, metadata: String? = nil)
    case invalidHTTPResponse(metadata: String? = nil)
    case serverError(statusCode : Int, metadata: String? = nil)
    case maxRetriesReached(metadata: String? = nil)
    case nonParsableResponse(metadata: String? = nil)
    case noData
    case failedJobRequest(metadata: String? = nil)
    case noDataToBeSent
    case jobError(status: String, code: String, title: String,
                  detail: String, source: [String : String],
                  metadata: String? = nil)

    // Human-readable error codes
    public var description: String {
        switch self {
        case .invalidCDSURL:
            return "The provided CDS url was invalid"
        case .noLocaleCodes:
            return "No locale codes were provided to the fetch operation"
        case .failedSerialization(let error):
            return "Translation strings to be pushed failed to be serialized (error: \(error))"
        case .requestFailed(let error, let metadata):
            return "CDS request failed with error: \(error)\(describe(metadata))"
        case .invalidHTTPResponse(let metadata):
            return "HTTP response received by CDS was invalid\(describe(metadata))"
        case .serverError(let statusCode, let metadata):
            return "CDS responded with \(statusCode) status code\(describe(metadata))"
        case .maxRetriesReached(let metadata):
            return "The operation exceeded max retries (\(CDSHandler.MAX_RETRIES))\(describe(metadata))"
        case .nonParsableResponse(let metadata):
            return "The server response could not be parsed\(describe(metadata))"
        case .noData:
            return "No data was received from the server response."
        case .failedJobRequest(let metadata):
            return "The job status request failed\(describe(metadata))"
        case .noDataToBeSent:
            return "There is no generated data to be sent to CDS"
        case .jobError(let status, let code, let title, let detail, let source,
                       let metadata):
            return """
A job error was returned by CDS\(describe(metadata)):
status: \(status)
code: \(code)
title: \(title)
detail: \(detail)
source: \(source)
"""
        }
    }

    private func describe(_ metadata: String?) -> String {
        if let metadata = metadata {
            return " (\(metadata))"
        }
        else {
            return ""
        }
    }
}

/// All possible warnings that may be produced when pushing strings to CDS.
public enum TXCDSWarning: Error {
    /// A duplicate source string pair has been detected.
    case duplicateSourceString(sourceString: String,
                               duplicate: String)
    /// A source string with an empty key has been detected.
    case emptyKey(SourceString: String)
}

/// Class that holds the configuration of the `pushTranslations()` method that controls various aspect
/// of the push to CDS.
public final class TXPushConfiguration : NSObject {
    /// Purge content
    ///
    /// If `purge`: true in meta object, then replace the entire resource content with the pushed content of
    /// this request.
    ///
    /// If `purge`: false in meta object (the default), then append the source content of this request to the
    /// existing resource content.
    @objc
    public let purge: Bool

    /// Replace tags
    ///
    /// If `overrideTags`: true in meta object, then replace the existing string tags with the tags of this
    /// request.
    ///
    /// If `overrideTags`: false in meta object (the default), then append tags from source content to
    /// tags of existing strings instead of overwriting them.
    @objc
    public let overrideTags: Bool

    /// Replace occurrences
    ///
    /// If `overrideOccurrences`: true in meta object, then replace the existing string occurrences with
    /// the occurrences of this request.
    ///
    /// If `overrideOccurrences`: false in meta object (the default), then append occurrences from
    /// source content to occurrences of existing strings instead of overwriting them.
    @objc
    public let overrideOccurrences: Bool

    /// Keep translations
    ///
    /// If `keepTranslations`: true in meta object (the default), then preserve translations on source
    /// content updates.
    ///
    /// If `keepTranslations`: false in meta object, then delete translations on source string content
    /// updates.
    @objc
    public let keepTranslations: Bool

    /// Dry run
    ///
    /// If `dryRun`: true in meta object, then emulate a content push, without doing actual changes.
    @objc
    public let dryRun: Bool

    /// Initialize the push configuration object with the provided parameters.
    ///
    /// Refer to the documentation of each property for default values and more information.
    ///
    /// - Parameters:
    ///   - purge: The purge content boolean flag.
    ///   - overrideTags: The override tags boolean flag.
    ///   - overrideOccurrences: The override occurrences boolean flag.
    ///   - keepTranslations: The keep translations boolean flag.
    ///   - dryRun: The dry run boolean flag.
    @objc
    public init(purge: Bool = false,
                overrideTags: Bool = false,
                overrideOccurrences: Bool = false,
                keepTranslations: Bool = true,
                dryRun: Bool = false) {
        self.purge = purge
        self.overrideTags = overrideTags
        self.overrideOccurrences = overrideOccurrences
        self.keepTranslations = keepTranslations
        self.dryRun = dryRun
    }

    /// Description of the configuration used for debugging purposes
    public override var debugDescription: String {
        """
TXPushConfiguration(purge: \(purge), overrideTags: \(overrideTags), overrideOccurrences: \(overrideOccurrences), keepTranslations: \(keepTranslations), dryRun: \(dryRun))
"""
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
            var overrideTags: Bool
            var overrideOccurrences: Bool
            var keepTranslations: Bool
            var dryRun: Bool

            enum CodingKeys: String, CodingKey {
                case purge
                case overrideTags = "override_tags"
                case overrideOccurrences = "override_occurrences"
                case keepTranslations = "keep_translations"
                case dryRun = "dry_run"
            }

            init(from configuration: TXPushConfiguration) {
                purge = configuration.purge
                overrideTags = configuration.overrideTags
                overrideOccurrences = configuration.overrideOccurrences
                keepTranslations = configuration.keepTranslations
                dryRun = configuration.dryRun
            }
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

    private struct RequestData : Codable {
        var data: TXLocaleStrings
    }

    private typealias CDSPullRequestResult = Result<TXLocaleStrings, TXCDSError>

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
        let totalRequests = requestsByLocale.count
        var translationsByLocale: TXTranslations = [:]
        var errors: [Error] = []
        
        for (code, requestByLocale) in requestsByLocale {
            performFetch(retryCount: 0,
                         code: code,
                         request: requestByLocale) { [weak self] result in
                guard let _ = self else {
                    return
                }

                requestsFinished += 1

                switch result {
                case .success(let localeStrings):
                    translationsByLocale[code] = localeStrings
                case .failure(let error):
                    errors.append(error)
                }

                if requestsFinished == totalRequests {
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

        session.dataTask(with: request) { [weak self] (data, response, error) in
            guard let _ = self else {
                return
            }
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
    ///   - configuration: A configuration object containing all the options that will be used alongside
    ///   the push operation (see `TXPushConfiguration`).
    ///   - completionHandler: A callback to be called when the push operation is complete with a
    /// boolean argument that informs the caller that the operation was successful (true) or not (false) and
    /// an array that may or may not contain any errors produced during the push operation and an array of
    /// non-blocking errors (warnings) that may have been generated during the push procedure.
    public func pushTranslations(_ translations: [TXSourceString],
                                 configuration: TXPushConfiguration = TXPushConfiguration(),
                                 completionHandler: @escaping (Bool, [TXCDSError], [TXCDSWarning]) -> Void) {
        let serializedResult = Self.serializeTranslations(translations,
                                                          configuration: configuration)
        switch serializedResult.0 {
        case .success(let jsonData):
            guard jsonData.count > 0 else {
                completionHandler(false, [.noDataToBeSent], serializedResult.1)
                return
            }
            Logger.verbose("Pushing translations to CDS: \(translations)...")
            pushData(jsonData,
                     warnings: serializedResult.1,
                     completionHandler: completionHandler)
        case .failure(let error):
            completionHandler(false, [.failedSerialization(error: error)], serializedResult.1)
        }
    }

    // MARK: - Private

    /// Performs the fetch (pull) request to CDS and offers a completion handler when the request succeeds
    /// or fails, with the associated Result type (CDSPullRequestResult).
    ///
    /// - Parameters:
    ///   - retryCount: The current retry count [0, CDSHandler.MAX_RETRIES]
    ///   - code: The locale code that is pulled from CDS
    ///   - request: The actual URLRequest
    ///   - requestCompleted: The completion handler.
    private func performFetch(retryCount: Int,
                              code: String,
                              request: URLRequest,
                              requestCompleted: @escaping (CDSPullRequestResult) -> Void) {
        session.dataTask(with: request) { [weak self]
            (data, response, error) in
            guard let self = self else {
                return
            }

            if let error = error {
                requestCompleted(.failure(.requestFailed(error: error,
                                                         metadata: code)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                requestCompleted(.failure(.invalidHTTPResponse(metadata: code)))
                return
            }

            let statusCode = httpResponse.statusCode

            switch statusCode {

            case CDSHandler.HTTP_STATUS_CODE_OK:
                if let data = data {
                    do {
                        let request = try JSONDecoder().decode(RequestData.self,
                                                               from: data)
                        requestCompleted(.success(request.data))
                    }
                    catch {
                        requestCompleted(.failure(.requestFailed(error: error,
                                                                 metadata: code)))
                    }
                }
                else {
                    requestCompleted(.failure(.nonParsableResponse(metadata: code)))
                }
            case CDSHandler.HTTP_STATUS_CODE_ACCEPTED:
                Logger.info("Received 202 response while fetching locale: \(code)")
                if retryCount < CDSHandler.MAX_RETRIES {
                    performFetch(retryCount: retryCount + 1,
                                 code: code,
                                 request: request,
                                 requestCompleted: requestCompleted)
                }
                else {
                    requestCompleted(.failure(.maxRetriesReached(metadata: code)))
                }
            default:
                requestCompleted(.failure(.serverError(statusCode: statusCode,
                                                       metadata: code)))
            }
        }.resume()
    }

    /// Pushes the generated JSON data containing the source strings and propagates any generated
    /// warnings to the final completion handler.
    ///
    /// - Parameters:
    ///   - jsonData: The generated JSON data
    ///   - warnings: Any generated CDS warnings that have been generated
    ///   - completionHandler: Callback function to be called when the push operation completes.
    private func pushData(_ jsonData: Data,
                          warnings: [TXCDSWarning],
                          completionHandler: @escaping (Bool, [TXCDSError], [TXCDSWarning]) -> Void) {
        guard let cdsHostURL = URL(string: configuration.cdsHost) else {
            completionHandler(false, [.invalidCDSURL], warnings)
            return
        }
        
        let baseURL = cdsHostURL.appendingPathComponent(CDSHandler.CONTENT_ENDPOINT)
        var request = URLRequest(url: baseURL)
        request.httpBody = jsonData
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = getHeaders(withSecret: true)

        session.dataTask(with: request) { [weak self] (data, response, error) in
            guard let self = self else {
                return
            }
            if let error = error {
                completionHandler(false, [.requestFailed(error: error)], warnings)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completionHandler(false, [.invalidHTTPResponse()], warnings)
                return
            }
            
            if httpResponse.statusCode != CDSHandler.HTTP_STATUS_CODE_ACCEPTED {
                completionHandler(false, [.serverError(statusCode: httpResponse.statusCode)], warnings)
                return
            }
            
            guard let data = data else {
                completionHandler(false, [.noData], warnings)
                return
            }
            
            let decoder = JSONDecoder()
            var response : PushResponseData? = nil
            
            do {
                response = try decoder.decode(PushResponseData.self,
                                              from: data)
            }
            catch { }
            
            guard let finalResponse = response else {
                completionHandler(false, [.nonParsableResponse()], warnings)
                return
            }
            
            self.pollJobStatus(jobURL: finalResponse.data.links.job,
                               warnings: warnings,
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
                               warnings: [TXCDSWarning],
                               retryCount: Int,
                               completionHandler: @escaping (Bool, [TXCDSError], [TXCDSWarning]) -> Void) {
        // Delay the job status request by 1 second, so that the server can
        // have enough time to process the job.
        Thread.sleep(forTimeInterval: 1.0)
        
        fetchJobStatus(jobURL: jobURL) { [weak self]
            jobStatus, jobErrors, jobDetails in
            guard let self = self else {
                return
            }
            guard let finalJobStatus = jobStatus else {
                completionHandler(false, [.failedJobRequest(metadata: jobURL)], warnings)
                return
            }
            
            var finalErrors: [TXCDSError] = []
            
            if let errors = jobErrors, errors.count > 0 {
                for error in errors {
                    finalErrors.append(.jobError(status: error.status,
                                                 code: error.code,
                                                 title: error.title,
                                                 detail: error.detail,
                                                 source: error.source,
                                                 metadata: jobURL))
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
                                           warnings: warnings,
                                           retryCount: retryCount + 1,
                                           completionHandler: completionHandler)
                    }
                    else {
                        completionHandler(false, [.maxRetriesReached(metadata: jobURL)], warnings)
                    }
                case .failed:
                    completionHandler(false, finalErrors, warnings)
                case .completed:
                    completionHandler(true, finalErrors, warnings)
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

        session.dataTask(with: request) { [weak self] (data, response, error) in
            guard let _ = self else {
                return
            }
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
    /// - Parameter configuration: A configuration object containing all the options that will be used alongside
    ///   the push operation (see `TXPushConfiguration`).
    /// - Returns: A tuple containing the Result object that either contains the Data object ready to be
    /// used in the CDS request or an error and the list of warnings generated during processing.
    private static func serializeTranslations(_ translations: [TXSourceString],
                                              configuration: TXPushConfiguration = TXPushConfiguration()) -> (Result<Data, Error>, [TXCDSWarning]) {
        var sourceStrings: [String:SourceString] = [:]
        var warnings: [TXCDSWarning] = []

        for translation in translations {
            let key = translation.key
            let sourceString = translation.sourceStringRepresentation()
            if let duplicateSourceString = sourceStrings[key] {
                warnings.append(.duplicateSourceString(sourceString: sourceString.debugDescription,
                                                       duplicate: duplicateSourceString.debugDescription))
            }
            if key.trimmingCharacters(in: .whitespacesAndNewlines).count == 0 {
                warnings.append(.emptyKey(SourceString: sourceString.debugDescription))
            }
            sourceStrings[key] = translation.sourceStringRepresentation()
        }

        let data = PushData(data: sourceStrings,
                            meta: PushData.Meta(from: configuration))

        return (Result { try JSONEncoder().encode(data) }, warnings)
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
