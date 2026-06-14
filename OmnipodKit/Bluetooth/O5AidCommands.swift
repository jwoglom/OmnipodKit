//
//  O5AidCommands.swift
//  OmnipodKit
//
//  Created for O5 AID setup commands sent between AssignAddress and SetupPod.
//  These use an ASCII key-value protocol different from legacy Omnipod commands.
//
//  Command formats:
//    SET+GET: S[feature].[attr]=[data],G[feature].[attr]
//    GET only: G[feature].[attr]
//    Extended SET: SE[feature].[attr]=[data]
//
//  Response formats:
//    SET+GET response: [feature].[attr]=[data]
//    GET response: [feature].[attr]=[data]
//    Extended SET response: ES[feature].[attr]=[data]
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

/// Constructs O5 AID command payloads for the pre-SetupPod activation sequence.
///
/// These commands use plain ASCII key-value format (NOT the SLPE length-prefixed encoding
/// used by standard S0.0= commands). The data values can be ASCII text
/// (e.g., "8" for DIA) or raw binary bytes (e.g., 0x0003000E00 for TDI).
///
struct O5AidCommands {

    // MARK: - AID Payload Construction
    //
    // AID commands use plain ASCII key-value format with NO length prefix.
    // This is different from standard Omnipod SLPE (S0.0=...,G0.0) which uses
    // 2-byte big-endian length prefixes via StringLengthPrefixEncoding.formatKeys().
    //
    // Confirmed wire format is: ASCII key + data + ASCII suffix
    // For BINARY commands, data is raw bytes. For ASCII commands, data is text.

    /// Constructs a SET+GET command payload with ASCII text data.
    ///
    /// Wire format: `S[f].[a]=[ASCII data],G[f].[a]`
    static func setGetPayload(feature: String, attribute: String, data: String) -> Data {
        let command = "S\(feature).\(attribute)=\(data),G\(feature).\(attribute)"
        return Data(command.utf8)
    }

    /// Constructs a SET+GET command payload with raw binary data.
    ///
    /// Wire format: `S[f].[a]=` + [raw binary bytes] + `,G[f].[a]`
    static func setGetPayload(feature: String, attribute: String, binaryData: Data) -> Data {
        let prefix = Data("S\(feature).\(attribute)=".utf8)
        let suffix = Data(",G\(feature).\(attribute)".utf8)
        return prefix + binaryData + suffix
    }

    /// Constructs a GET-only command payload.
    ///
    /// Wire format: `G[f].[a]`
    static func getPayload(feature: String, attribute: String) -> Data {
        let command = "G\(feature).\(attribute)"
        return Data(command.utf8)
    }

    /// Constructs a SET-only command payload with ASCII text data (no trailing GET).
    ///
    /// Wire format: `S[f].[a]=[ASCII data]`
    ///
    /// This differs from `setGetPayload`, which always appends `,G[f].[a]`. The
    /// periodic-command configuration command (see `PeriodicCommandConfig`) uses
    /// this SET-only shape — the iOS app's static decode shows the config command
    /// has no GET suffix.
    static func setOnlyPayload(feature: String, attribute: String, data: String) -> Data {
        let command = "S\(feature).\(attribute)=\(data)"
        return Data(command.utf8)
    }

    /// Constructs an Extended SET command payload with ASCII text data.
    ///
    /// Wire format: `SE[f].[a]=[ASCII data]`
    static func extendedSetPayload(feature: String, attribute: String, data: String) -> Data {
        let command = "SE\(feature).\(attribute)=\(data)"
        return Data(command.utf8)
    }

    /// Constructs an Extended SET command payload with raw binary data.
    ///
    /// Wire format: `SE[f].[a]=` + [raw binary bytes]
    static func extendedSetPayload(feature: String, attribute: String, binaryData: Data) -> Data {
        let prefix = Data("SE\(feature).\(attribute)=".utf8)
        return prefix + binaryData
    }

    /// Returns the expected response prefix for a SET+GET or GET-only command.
    /// Response format: `[feature].[attribute]=`
    static func responsePrefix(feature: String, attribute: String) -> String {
        return "\(feature).\(attribute)="
    }

    /// Returns the expected response prefix for an Extended SET command.
    /// Response format: `ES[feature].[attribute]=`
    static func extendedSetResponsePrefix(feature: String, attribute: String) -> String {
        return "ES\(feature).\(attribute)="
    }

    // MARK: - AID Command Definitions

    /// Command 1: UTC time setting.
    /// Sends: `SE255.2=[unix_timestamp]`
    /// Response: `ES255.2=0`
    struct UtcCommand {
        static let feature = "255"
        static let attribute = "2"

        /// Creates the SLPE-wrapped payload for the UTC command.
        /// - Parameter timestamp: Unix timestamp (defaults to current time)
        /// - Returns: Tuple of (payload, responsePrefix)
        static func payload(timestamp: UInt64? = nil) -> (data: Data, responsePrefix: String) {
            let ts = timestamp ?? UInt64(Date().timeIntervalSince1970)
            let data = O5AidCommands.extendedSetPayload(feature: feature, attribute: attribute, data: "\(ts)")
            let prefix = O5AidCommands.extendedSetResponsePrefix(feature: feature, attribute: attribute)
            return (data, prefix)
        }
    }

    /// Command 2: TDI (Therapy Delivery Information) configuration.
    /// Binary wire format: `S3.2=` + [0x00,0x03,0x00,0x0E,0x00] + `,G3.2` (15 bytes)
    /// Response: `3.2=` + [5 binary bytes echoed back]
    ///
    /// The 5 data bytes: version(00), therapy type(03), delivery mode(00), bolus speed(0E=14U TDI), reserved(00).
    struct TdiCommand {
        static let feature = "3"
        static let attribute = "2"
        static let defaultBinaryData = Data([0x00, 0x03, 0x00, 0x0E, 0x00])

        static func payload() -> (data: Data, responsePrefix: String) {
            let payload = O5AidCommands.setGetPayload(feature: feature, attribute: attribute, binaryData: defaultBinaryData)
            let prefix = O5AidCommands.responsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    /// Command 3: Target BG profile — 48 half-hour BG target values for a 24-hour day.
    /// Binary wire format: `S3.1=` + [0x00,0xC0] + [48 x 4-byte-BE targets] + `,G3.1` (204 bytes)
    /// Response: `3.1=` + [194 binary bytes echoed back]
    ///
    /// The 0x00C0 prefix = 192 = 48 * 4 (byte count of the 48 target entries).
    /// Each target is a 4-byte big-endian value in mg/dL (e.g., 0x0000006E = 110).
    struct TargetBgProfileCommand {
        static let feature = "3"
        static let attribute = "1"
        static let defaultTargetMgdl: UInt32 = 110  // 0x006e

        static func payload(targets: [UInt32]? = nil) -> (data: Data, responsePrefix: String) {
            let targetValues = targets ?? Array(repeating: defaultTargetMgdl, count: 48)
            assert(targetValues.count == 48, "Target BG profile must have exactly 48 half-hour entries")

            var binaryData = Data()
            let totalBytes = UInt16(targetValues.count * 4)  // 192 = 0x00C0
            binaryData.appendBigEndian(totalBytes)
            for target in targetValues {
                binaryData.appendBigEndian(target)
            }
            let payload = O5AidCommands.setGetPayload(feature: feature, attribute: attribute, binaryData: binaryData)
            let prefix = O5AidCommands.responsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    /// Command 4: DIA (Duration of Insulin Action) setting.
    /// Sends: `S3.9=8,G3.9`
    /// Response: `3.9=8`
    ///
    /// Value "8" likely represents 8 half-hours = 4 hours DIA, but could be the raw value.
    struct DiaCommand {
        static let feature = "3"
        static let attribute = "9"
        static let defaultValue = "8"

        static func payload(value: String = defaultValue) -> (data: Data, responsePrefix: String) {
            let payload = O5AidCommands.setGetPayload(feature: feature, attribute: attribute, data: value)
            let prefix = O5AidCommands.responsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    /// Command 5: EGV (Estimated Glucose Value) configuration.
    /// Sends: `S3.7=3670015,G3.7`
    /// Response: `3.7=3670015`
    ///
    /// The value `3670015` is a bitfield or composite config value for CGM/EGV settings.
    struct EgvCommand {
        static let feature = "3"
        static let attribute = "7"
        static let defaultValue = "3670015"

        static func payload(value: String = defaultValue) -> (data: Data, responsePrefix: String) {
            let payload = O5AidCommands.setGetPayload(feature: feature, attribute: attribute, data: value)
            let prefix = O5AidCommands.responsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    /// Command 6: Algorithm Insulin History — sent 3 times with 24 records each.
    /// Binary wire format: `SE2.1=` + [0x00,0xA8] + [168 raw bytes] (176 bytes)
    /// Response: `ES2.1=0`
    ///
    /// The 0x00A8 prefix = 168 = 24 * 7 (byte count of the 24 history records).
    /// Each record is 7 bytes. For initial setup with no history, all records are zeros.
    struct AlgorithmInsulinHistoryCommand {
        static let feature = "2"
        static let attribute = "1"
        static let recordsPerBatch = 24
        static let bytesPerRecord = 7

        static func payload(records: [Data]? = nil) -> (data: Data, responsePrefix: String) {
            let recordData: [Data]
            if let records = records {
                assert(records.count == recordsPerBatch, "Must have exactly \(recordsPerBatch) records")
                recordData = records
            } else {
                // Default: 24 zero records of 7 bytes each
                recordData = Array(repeating: Data(count: bytesPerRecord), count: recordsPerBatch)
            }

            let totalBytes = UInt16(recordsPerBatch * bytesPerRecord)  // 168 = 0x00A8
            var binaryData = Data()
            binaryData.appendBigEndian(totalBytes)
            for record in recordData {
                assert(record.count == bytesPerRecord, "Each record must be exactly \(bytesPerRecord) bytes")
                binaryData.append(record)
            }
            let payload = O5AidCommands.extendedSetPayload(feature: feature, attribute: attribute, binaryData: binaryData)
            let prefix = O5AidCommands.extendedSetResponsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    /// Command 7 (Gen1): AID Pod Status query.
    /// Sends: `G3.11`
    /// Response: `3.11=[fixed 30-byte payload: 2-byte length + 28-byte body]`
    ///
    /// Used for Gen1 pods (firmware majorVersion < 7).
    struct AidPodStatusCommand {
        static let feature = "3"
        static let attribute = "11"

        static func payload() -> (data: Data, responsePrefix: String) {
            let payload = O5AidCommands.getPayload(feature: feature, attribute: attribute)
            let prefix = O5AidCommands.responsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    /// Command 7 (non-Gen1): Unified AID Pod Status query.
    /// Sends: `G3.12`
    /// Response: `3.12=[29 bytes of AID status data]`
    ///
    /// Used for non-Gen1 pods (firmware majorVersion >= 7).
    struct UnifiedAidPodStatusCommand {
        static let feature = "3"
        static let attribute = "12"

        static func payload() -> (data: Data, responsePrefix: String) {
            let payload = O5AidCommands.getPayload(feature: feature, attribute: attribute)
            let prefix = O5AidCommands.responsePrefix(feature: feature, attribute: attribute)
            return (payload, prefix)
        }
    }

    // MARK: - Periodic Command Configuration (EXPERIMENTAL — UNCONFIRMED ON THE WIRE)
    //
    // Reconstructed from a static decode of the iOS Omnipod 5 app (TWISDK). This
    // builds the *configuration* command that asks the pod to autonomously emit a
    // chosen command (in practice: the Status poll) on a fixed interval — the
    // pod-driven "heartbeat".
    //
    // ┌──────────────────────────────────────────────────────────────────────┐
    // │ IMPORTANT: building this payload is harmless and unit-testable, but    │
    // │ ACTUALLY SENDING it is NOT yet safe. The current OmnipodKit transport  │
    // │ is strictly synchronous request→single-response→ACK (see              │
    // │ BleMessageTransport.sendO5AidCommand). It has no always-on consumer    │
    // │ for the unsolicited Status frames the pod would then push onto the     │
    // │ DATA characteristic. Those frames would land in the shared dataQueue   │
    // │ and be mis-consumed as the next command's response (wrong payload +    │
    // │ wrong decrypt nonce → comms break / "queue poisoning"). A decrypt-     │
    // │ then-route RX path plus out-of-band nonce/seq/msgSeq handling and      │
    // │ per-emission ACKs must land first. See                                 │
    // │ analysis/omnipodkit_periodic_command_design.md.                        │
    // └──────────────────────────────────────────────────────────────────────┘
    //
    // Wire format (iOS template `SN%@.0=%d`):
    //   S  N<command-list> . 0 = <period-seconds>     (SET-only, no `,G` suffix)
    //   e.g. Status every 60s → "SN2.0=60" = 53 4E 32 2E 30 3D 36 30
    //   disable → period 0 → "SN2.0=0"
    //
    // UNCONFIRMED / open questions (do not treat the bytes as final):
    //   • Command-list token rendering: iOS maps each app command id through
    //     TWICommandIds.getSDKReservedCommandId: and joins tokens with spaces
    //     ("%@ %@ "). Whether Status renders as "2", a name string, or a numeric
    //     AID id — and how multiple tokens are delimited inside the feature slot
    //     — is unresolved without a Frida hook on the iOS -stringWithFormat: site.
    //     We default to "2" (TWICommandIds id 2 = Status) for a single command.
    //   • Period upper bound (~288000s / 80h) is r2's read of an fcmp and is NOT
    //     independently confirmed. The 60s lower bound and 0=disable ARE confirmed.
    //   • Response/ack format for this SET-only command is not byte-confirmed.
    struct PeriodicCommandConfig {
        static let feature = "N"
        static let attribute = "0"

        /// TWICommandIds id for the pod Status command (the periodic payload).
        static let statusCommandToken = "2"

        /// Confirmed lower bound on the period, in seconds (iOS `fcmp d8, 60.0`).
        static let minPeriodSeconds = 60
        /// UNCONFIRMED upper bound (iOS r2 read of `fcmp d8, 288000.0`, ~80h).
        static let maxPeriodSecondsUnconfirmed = 288000
        /// Period value that disables periodic emission (iOS `fmov d0, xzr`).
        static let disablePeriodSeconds = 0

        enum ConfigError: Error {
            /// Period was non-zero but below the confirmed 60s floor.
            case periodBelowMinimum(Int)
        }

        /// Builds the periodic-command configuration payload.
        ///
        /// - Parameters:
        ///   - periodSeconds: emission interval in seconds. `0` disables periodic
        ///     emission. Any other value must be ≥ `minPeriodSeconds` (60).
        ///   - commandTokens: the TWICommandIds tokens to register; defaults to
        ///     `[statusCommandToken]` (Status only). NOTE: multi-token delimiting
        ///     is unconfirmed (see type doc); tokens are currently concatenated.
        /// - Returns: `(data, responsePrefix)` in the same shape as the other
        ///   `O5AidCommands` builders. The `responsePrefix` is a best-effort guess
        ///   (`N<list>.0=`) and is NOT byte-confirmed.
        static func payload(periodSeconds: Int,
                            commandTokens: [String] = [statusCommandToken]) throws -> (data: Data, responsePrefix: String) {
            if periodSeconds != disablePeriodSeconds && periodSeconds < minPeriodSeconds {
                throw ConfigError.periodBelowMinimum(periodSeconds)
            }
            let list = commandTokens.joined()
            let featureWithList = feature + list   // "N" + "2" → "N2"
            let data = O5AidCommands.setOnlyPayload(feature: featureWithList,
                                                    attribute: attribute,
                                                    data: "\(periodSeconds)")
            let prefix = O5AidCommands.responsePrefix(feature: featureWithList, attribute: attribute)
            return (data, prefix)
        }
    }
}
