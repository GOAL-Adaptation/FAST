/*
 *  FAST: An implicit programing language based on Swift
 *
 *        REST client for the Machine Learning mode
 *
 *  author: Ryuichi Sai
 *
 */

//---------------------------------------

import Foundation
import LoggerAPI

//---------------------------------------

class MLClient {
  static func setup(_ initJSON: [String: Any]?) -> [String: Any]? {
    return RestClient.sendRequest(
      to: "setup",
      at: "localhost",
      onPort: 5000,
      withBody: initJSON
    )
  }

  static func update(_ json: [String: Any]?) -> [String: Any]? {
    return RestClient.sendRequest(
      to: "update",
      at: "localhost",
      onPort: 5000,
      withBody: json
    )
  }
}
