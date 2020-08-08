//
//  CDSHandler.swift
//  
//
//  Created by Dimitrios Bendilas on 3/8/20.
//

import Foundation

//let CDS_HOST = "https://rest.api.transifex.com"
let CDS_HOST = "http://tx.loc:10300"

/**
 Handles communication with the Content Delivery Service.
 */
class CDSHandler {

    // a list of locale codes for the configured languages in the application
    var localeCodes: [String] = []
    
    // the API token to use for connecting to the CDS
    var token: String = ""
    
    // the API secret to use for connecting to the CDS
    var secret: String?
    
    // the host of the Content Delivery Service
    var cdsHost: String = ""
    
    // an etag per locale code, used for optimizing requests
    var etagByLocale: [String: String] = [:]
    
    /**
     Constructor.
     - locales: a list of locale codes for the configured languages in the application
     - token: the API token to use for connecting to the CDS
     - secret: the API secret to use for connecting to the CDS
     - cdsHost: the host of the Content Delivery Service
     */
    init(localeCodes: [String], token: String, secret: String? = nil, cdsHost: String? = CDS_HOST) {
        self.localeCodes = localeCodes
        self.token = token
        self.secret = secret
        self.cdsHost = cdsHost != nil ? cdsHost! : CDS_HOST
    }
    
    /**
     Fetch translations from CDS.
     
       - localeCode: an optional locale to fetch translations from; if none provided it will fetch translations for all locales defined in the configuration
       - completionHandler: a function to call when the operation is complete
     */
    public func fetchTranslations(localeCode: String? = nil, completionHandler: @escaping ([String: LocaleStrings], Error?) -> Void) {
        let urlString = "\(cdsHost)/content/{localeCode}"
        
        var localeCodes: [String]
        if localeCode == nil {
            localeCodes = TxNative.locales.appLocales
        }
        else {
            localeCodes = [localeCode!]
        }
        
        var translations: [String: LocaleStrings] = [:]
        var cnt = 1
        for code in localeCodes {
            let url = URL(string: urlString.replacingOccurrences(of: "{localeCode}", with: code))!
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = getHeaders(withSecret: false)

            let session = URLSession(configuration: .default)
            print("Making requst to \(url.absoluteString)")
            // TODO: after the initial request that returns status=202, poll again until
            // translations are returned, or an erroreous status is returned
            let task = session.dataTask(with: request) { (data, response, error) in
                print("Response arrived! \(String(describing: data))")
                print("  response: \(String(describing: response))")
                print("  error:\(String(describing: error))")
                cnt += 1
                if error == nil {
                    translations[code] = [:]
                }
            }
            task.resume()
            
        }
        if cnt == localeCodes.count {
            completionHandler(translations, nil)
        }
    }
    
    /**
     Serialize the given source strings to a format suitable for the CDS.
     - strings: a list of `SourceString` objects
     - return: a dictionary
     */
    private func serializeSourceStrings(_ strings: [SourceString]) -> [String: [String: Any]] {
        var sourceStrings: [String: [String: Any]] = [:]
        for string in strings {
            sourceStrings[string.key] = [
                "string": string.string,
                "meta": [
                    "context": string.context,
                    "developer_comment": string.comment,
                    "character_limit": string.characterLimit,
                    "tags": string.tags,
                ]
            ]
        }
        return sourceStrings
    }

    /**
     Return the headers to use when making requests.
     - withSecret: if true, the Bearer authorization header will also include the secret, otherwise it will only use the token
     - etag: an optional etag to include for optimization
     - return: a dictionary with all headers
     */
    private func getHeaders(withSecret: Bool = false, etag: String? = nil) -> [String: String] {
        let secretPart = withSecret ? ":\(secret!)" : ""
        var headers = [
            "Authorization": "Bearer \(token)\(secretPart)",
            "Accept-Encoding": "gzip",
            "Content-Type": "application/json",
        ]
        if etag != nil {
            headers["If-None-Match"] = etag!
        }
        return headers
    }
    
    
}
