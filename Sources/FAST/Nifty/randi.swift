/***************************************************************************************************
 *  randi.swift
 *
 *  This file provides random integer functionality.
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

/// Internal structure for generating uniform random numbers. Random number generation throughout
/// Nifty should use this object as a base.
///
/// Algorithm based on:
/// Press, William H. "Numerical recipes 3rd edition: The art of scientific computing.", Cambridge
/// university press, 2007. Chapter 7.1, pg 342-343.
///
/// The period of the generator is about 3.138E57.
internal class UniformRandomGenerator
{
    var u: UInt64
    var v: UInt64
    var w: UInt64

    init(seed j: UInt64)
    {
        self.v = 4101842887655102017
        self.w = 1
        self.u = j ^ self.v
        let _ = self.uint64()
        self.v = self.u
        let _ = self.uint64()
        self.w = self.v
        let _ = self.uint64()
    }

    func uint64() -> UInt64
    {
        self.u = (self.u.multipliedReportingOverflow(by: 2862933555777941757).0)
            .addingReportingOverflow(7046029254386353087).0
        self.v ^= self.v >> 17
        self.v ^= self.v << 31
        self.v ^= self.v >> 8
        let w_temp = (4294957665 as UInt64).multipliedReportingOverflow(by: self.w & 0xffffffff).0
        self.w = w_temp.addingReportingOverflow(self.w >> 32).0
        var x: UInt64 = self.u ^ (self.u << 21)
        x ^= x >> 35
        x ^= x << 4
        let retVal = x.addingReportingOverflow(self.v).0 ^ self.w

        return retVal
    }

    func uint32() -> UInt32
    {
        return UInt32(self.uint64() >> 32)
    }

    func doub() -> Double
    {
        // TODO: Revist and test the need to use only 53 bits. Is it really necessary?
        // Integers up to 2^53-1 can be stored in double without loss of precision. Beyond that,
        // precision may be lost, which would mean multiple UInt64s may map to same double, throwing
        // off uniformity. Use only 53 bits of UInt64 to prevent this and multiply by 1/(2^53-1)
        return 1.110223024625156786942664549657E-16  * Double(self.uint64() >> 11)
    }
}

// Global random number generator instance used for generation of uniform randoms, unless function
// is called with the `threadSafe` option set.
internal var g_UniformRandGen: UniformRandomGenerator? = nil

//==================================================================================================
// MARK: PUBLIC RANDI INTERFACE
//==================================================================================================

import Foundation

/// Return a matrix of random whole numbers in the specified range.
///
/// - Note: If large amounts of random numbers are needed, it's more efficient to request one large
///    matrix rather than many individual numbers.
/// - Note: Generated numbers are limited to a maximum magnitude of 2^53-1; this ensures that they
///    can be stored as Doubles without loss of precision. Furthemore, the most negative number that
///    can be generated is Int.min+1, not Int.min; this is so the range `min-max` can be computed
///    without overflow.
/// - Parameters:
///    - rows: number of rows in matrix to generate
///    - columns: number of columns in matrix to generate
///    - min: optionally specify minimum integer value to return, inclusive
///    - max: optionally specify maximum integer value to return, inclusive
///    - seed: optionally provide specific seed for generator. If threadSafe is set, this seed will
///        not be applied to global generator, but to the temporary generator instance
///    - threadSafe: if set to true, a new random generator instance will be created that will be
///        be used and exist only for the duration of this call. Otherwise, global instance is used.
/// - Returns: matrix of whole numbers
public func randi(min: Int32 = 0, max: Int32 = Int32.max, seed: UInt64? = nil) -> Double {
  let range: UInt
  if max >= 0 && min < 0 {
    range = UInt(max) + UInt(abs(min))
  } else {
    range = UInt(max - min)
  }

  var curRandGen: UniformRandomGenerator

  if let s = seed {
    curRandGen = UniformRandomGenerator(seed: s)
    g_UniformRandGen = curRandGen
  } else if let gen = g_UniformRandGen {
    curRandGen = gen
  } else{
    curRandGen = UniformRandomGenerator(seed: UInt64(Date().timeIntervalSince1970*10000))
    g_UniformRandGen = curRandGen
  }
  let bits = UInt64(msb(range))
  let mask: UInt64
  if bits == 64 {
    mask = UInt64.max
  } else {
    mask = (UInt64(1) << bits)-1
  }

  while true {
    let r64 = curRandGen.uint64()
    for chunkIndex in 0..<(64/bits) {
      let bitChunk = (r64 >> UInt64(chunkIndex*bits)) & mask

      if bitChunk <= UInt64(range) {
        return Double(Int32(bitChunk)+min)
      }
    }
  }
}
