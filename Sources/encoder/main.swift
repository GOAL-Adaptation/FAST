/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Example application: Encoder
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Foundation
import FAST

let quality = Knob("quality", 10)
let framerate = Knob("framerate", 10)

optimize("encoder", [quality, framerate]) {
    if 
        let m = ProcessInfo.processInfo.environment["mode"], 
        m == "highQuality" 
    {
        quality.restrict([10])
    } else {
        quality.control()
    }
    let bitrate = quality.get() * framerate.get() * 100
    usleep(UInt32(bitrate)) // Encode frame at given bitrate
    measure("bitrate", Double(bitrate))
}
