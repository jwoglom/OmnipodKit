//
//  MessageLogger.swift
//  OmnipodKit
//
//  Taken from  on OmniKit/MessageTransport/MessageTransport.swift
//  Created by Joe Moran on 1/9/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log

protocol MessageLogger: AnyObject {
    // Comms logging
    func didSend(_ message: Data)
    func didReceive(_ message: Data)
    func didError(_ message: String)

    // [RX-OBSERVE] Free-form observation logging for the pod-driven-heartbeat
    // investigation. Lets low-level BLE layers (PeripheralManager) surface a
    // pre-formatted string up to OmniPumpManager.logDeviceCommunication so it
    // lands in Trio's exportable in-app device log (not just Apple unified
    // logging). Observation-only; no comms behavior depends on it.
    func observe(_ message: String)
}

extension MessageLogger {
    // Default no-op so existing conformers are unaffected if they don't
    // implement observe(_:).
    func observe(_ message: String) {}
}
