/*
 *  FAST: An implicit programing language based on Swift
 *
 *        JSON Conversions for FAST Models
 *
 *  authors: Ryuichi Sai, Adam Duracz
 */

//-------------------------------

import Foundation
import LoggerAPI

extension Model {
  func toSetupJSON(id: String, intent: IntentSpec) -> [String: Any]? {
    var arguments: [String: Any] = ["application": id]

    arguments["knobs"] = intent.knobs.map { (name: String, rangeAndReferenceValue: ([Any],Any)) in
      return [
        "name": name,
        "range": rangeAndReferenceValue.0,
      ]
    }

    arguments["knobTable"] = configurations
      .map { $0.knobSettings }
      .map { knob -> [String: Any] in
        let knobSettings = knob.settings.map { (key, value) in
          [
            "name": key,
            "value": value,
          ]
        }
        return ["id": knob.kid, "values": knobSettings]
      }

    arguments["featureTable"] = [
      [
        "id": 0,
        "values": [
          [
            "name": "dummy",
            "value": 0,
          ],
        ],
      ],
    ]

    arguments["measureTable"] = configurations
      .map { ($0.id, $0.knobSettings.kid, $0.measureNames, $0.measureValues) }
      .map { (id: Int, kid: Int, names: [String], values: [Double]) -> [String: Any] in
        let values = zip(names, values).map { ["name": $0.0, "value": $0.1] }
        return [
          "id": id,
          "kid": kid,
          "fid": 0,
          "values": values
        ]
      }

    let mlJSON: [String: Any] = [
      "time": utcDateString(),
      "arguments": arguments,
    ]

    return mlJSON
  }

  func toUpdateJSON(id: String, lastWindowConfigIds: [Int], lastWindowMeasures: [String: [Double]]) -> [String: Any]? {
    var arguments: [String: Any] = ["application": id]

    arguments["knobTable"] = configurations
      .map { $0.knobSettings }
      .map { knob -> [String: Any] in
        let knobSettings = knob.settings.map { (key, value) in
          [
            "name": key,
            "value": value,
          ]
        }
        return ["id": knob.kid, "values": knobSettings]
      }

    arguments["featureTable"] = [
      [
        "id": 0,
        "values": [
          [
            "name": "dummy",
            "value": 0,
          ],
        ],
      ],
    ]

    let totalCount = lastWindowConfigIds.count
    let newMeasureTable = lastWindowConfigIds.enumerated()
      .map { (id: Int, kid: Int) -> (Int, Int, [String: Double]) in
        var values: [String: Double] = [:]
        for (k, vs) in lastWindowMeasures {
          values[k] = vs[totalCount - id - 1]
        }
        return (id, kid, values)
      }
      .map { (id: Int, kid: Int, values: [String: Double]) -> [String: Any] in
        return [
          "id": id,
          "kid": kid,
          "fid": 0,
          "values": values.map { ["name": $0, "value": $1] }
        ]
      }
    Log.debug("New measure table: \(newMeasureTable)")

    arguments["measureTable"] = configurations
      .map { ($0.id, $0.knobSettings.kid, $0.measureNames, $0.measureValues) }
      .map { (id: Int, kid: Int, names: [String], values: [Double]) -> [String: Any] in
        let values = zip(names, values).map { ["name": $0.0, "value": $0.1] }
        return [
          "id": id,
          "kid": kid,
          "fid": 0,
          "values": values
        ]
      }

    let mlJSON: [String: Any] = [
      "time": utcDateString(),
      "arguments": arguments,
    ]

    return mlJSON
  }

  convenience init?(fromMachineLearning json: [String: Any], intent: IntentSpec) {
    guard
      let measureTable = json["measureTable"] as? [[String: Any]],
      let knobTable = json["knobTable"] as? [[String: Any]],
      !measureTable.isEmpty,
      !knobTable.isEmpty
    else { return nil }

    func extract(from table: [[String: Any]]) -> [(Int, [String: Any])] {
      return table.compactMap { t -> (Int, [String: Any])? in
        guard let tid = t["id"] as? Int, let tvalues = t["values"] as? [[String: Any]] else { return nil }
        let tNameValuePair = tvalues.compactMap { values -> (String, Any)? in
          guard let name = values["name"] as? String, let value = values["value"] else { return nil }
          if let doubleValue = value as? Double, floor(doubleValue) == doubleValue {
            return (name, Int(doubleValue))
          }
          return (name, value)
        }
        guard tNameValuePair.count == tvalues.count else { return nil }
        let tValueMap = tNameValuePair.reduce([String: Any]()) { carryOver, e in
          var carryOver = carryOver
          carryOver[e.0] = e.1
          return carryOver
          // return carryOver.merging([e.0: e.1]) { $0.1 } // TODO: when we upgrade to Swift 4+
        }
        return (tid, tValueMap)
      }
    }

    func csvGen(basedOn pairs: [(Int, [String: Any])]) -> String {
      if pairs.isEmpty { return "" }

      let names = ["id"] + Array(pairs[0].1.keys)
      let header = names.joined(separator: ",")
      let body = pairs.map { k in
        (["\(k.0)"] + Array(k.1.values.map { "\($0)" })).joined(separator: ",")
      }
      return ([header] + body).joined(separator: "\n")
    }

    let knobs = extract(from: knobTable)
    guard knobs.count == knobTable.count else { return nil }
    let knobCSVContent = csvGen(basedOn: knobs)

    let measures = extract(from: measureTable)
    guard measures.count == measureTable.count else { return nil }
    let measureCSVContent = csvGen(basedOn: measures)

    self.init(knobCSVContent, measureCSVContent, intent)
  }
}

//-------------------------------
