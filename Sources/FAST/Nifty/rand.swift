/***************************************************************************************************
 *  rand.swift
 *
 *  This file provides random decimal number functionality.
 *
 *  Author: Philip Erickson
 *  Creation Date: 1 May 2016
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License. You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software distributed under the
 *  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 *  express or implied. See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  Copyright 2016 Philip Erickson
 **************************************************************************************************/

import Dispatch
import Foundation

public func rand(min: Double = 0.0, max: Double = 1.0, seed: UInt64? = nil) -> Double {
  let range = max-min

  var curRandGen: UniformRandomGenerator
  if let s = seed {
    curRandGen = UniformRandomGenerator(seed: s)
    g_UniformRandGen = curRandGen
  } else if let gen = g_UniformRandGen {
    curRandGen = gen
  } else {
    curRandGen = UniformRandomGenerator(seed: UInt64(Date().timeIntervalSince1970*1000000))
    g_UniformRandGen = curRandGen
  }

  let r = curRandGen.doub()
  return r * range + min
}
