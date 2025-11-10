//
//  AudioPacketProtocol.swift
//  AirCast
//
//  Created by Janavi Bathala Vijayabhaskar on 11/6/25.
//

import Foundation

/* Audio codecs supported by AirCast */

enum AudioCodec: UInt8{
    case pcm = 96
    case aac = 97
    case alac = 98
    
    var name: String{
        switch self{
        case .pcm: return "PCM"
        case .aac: return "AAC"
        case .alac: return "ALAC"
        }
    }
    
    var typicalBitRate: Int{
        switch self{
        case .pcm: return 1411
        case .aac: return 256
        case .alac: return 600
        }
    }
}

/* RTP header - 12 bytes, from the standard */

struct RTPHeader{
    let version: UInt8 // 2 bits
    let padding: Bool  // 1 bit
    let hasExtension: Bool  // 1 bit
    let csrcCount: UInt8  // 4 bits - concludes byte 0
    
    let marker: Bool  // 1 bit
    let payloadType: UInt8  // 7 bits - concludes byte 1
    
    let seqNumber: UInt16 // bytes 2 - 3
    
    let timestamp: UInt32      // bytes 4 - 7
    
    let ssrc: UInt32           // bytes 8 - 11
    
    //   let csrcs: [UInt32]  /* TBD */
    
    init(version: UInt8 = 2,
         padding: Bool = false,
         hasExtension: Bool = true, /* for metadata */
         csrcCount: UInt8 = 0,
         marker: Bool = false,
         payloadType: UInt8,
         seqNumber: UInt16,
         timestamp: UInt32,
         ssrc: UInt32) {
        
        self.version = version
        self.padding = padding
        self.hasExtension = hasExtension
        self.csrcCount = csrcCount
        self.marker = marker
        self.payloadType = payloadType
        self.seqNumber = seqNumber
        self.timestamp = timestamp
        self.ssrc = ssrc
    }
    
    
    /* Serialization - network-byte order (Big Endian)
                     - RTP header to Raw Binary Data */
    
    func toData() -> Data{
        var data = Data()
        
        /* Byte 0 */
        var byte0: UInt8 = 0
        byte0 |= (version & 0x03) << 6
        byte0 |= (padding ? 1 : 0) << 5
        byte0 |= (hasExtension ? 1 : 0) << 4
        byte0 |= (csrcCount & 0x0F)
        data.append(byte0)
        
        /* Byte 1 */
        var byte1: UInt8 = 0
        byte1 |= (marker ? 1 : 0) << 7
        byte1 |= (payloadType & 0x7F)
        data.append(byte1)
        
        /* Bytes 2 - 3 */
        data.append(contentsOf: withUnsafeBytes(of: seqNumber.bigEndian) { Data($0) }) //closure - like callback in C
                    
        /* Bytes 4 - 7 */
        data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Data($0) })
                    
        /* Bytes 8 - 11 */
        data.append(contentsOf: withUnsafeBytes(of: ssrc.bigEndian) { Data($0) })
                    
        return data
    }
    
    /* Deserialization : Raw binary data to RTP Header */
    static func from(_ data: Data) -> RTPHeader? {
        guard data.count >= 12
        else
        {
            return nil
        }
        
    /* Byte 0 */
        let byte0 = data[0]
        let version = (byte0 >> 6) & 0x03
        let padding = ((byte0 >> 5) & 0x01) == 1
        let hasExtension = ((byte0 >> 4) & 0x01) == 1
        let csrcCount = byte0 & 0x0F
        
    /* Byte 1 */
        let byte1 = data[1]
        let marker = ((byte1 >> 7) & 0x01) == 1
        let payloadType = byte1 & 0x7F
        
    /* Bytes 2 - 3*/
        let seqNumber = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
    /* Bytes 4 - 7 */
        let timestamp = data.subdata(in: 4..<8).withUnsafeBytes({ $0.load(as: UInt32.self).bigEndian })
        
    /* Bytes 8 - 11 */
        let ssrc = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        return RTPHeader(
            version: version,
            padding: padding,
            hasExtension: hasExtension,
            csrcCount: csrcCount,
            marker: marker,
            payloadType: payloadType,
            seqNumber: seqNumber,
            timestamp: timestamp,
            ssrc: ssrc
        )
    }
}

/* Custom AirCast header - 8 bytes */

struct AirCastExtension{
    /* Audio Format */
    let codec: AudioCodec /* 1 byte - codec */
    let channels: UInt8  /* 1 byte - # of channels */
    let sampleRate: UInt16 /* 2 bytes - Sample rate in Hz */
    
    /* Control */
    let volume: UInt8
    let flags: UInt8
    
    /* Reserved for future use */
    let reserved: UInt16
    
    /* Control flags */
    struct Flags{
        static let sync: UInt8 = 1 << 0
        static let keyFrame: UInt8 = 1 << 1
        static let endOfStream: UInt8 = 1 << 2
    }
    
    /* Initialization */
    
    init(codec: AudioCodec,
         channels: UInt8,
         sampleRate: UInt16,
         volume: UInt8 = 83,
         flags: UInt8 = 0,
         reserved: UInt16 = 0){
        
        self.codec = codec
        self.channels = channels
        self.sampleRate = sampleRate
        self.volume = volume
        self.flags = flags
        self.reserved = reserved
    }
    
    /* Serialization */
    
    func toData() -> Data{
        var data =  Data()
        
        data.append(codec.rawValue)
        data.append(channels)
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.bigEndian) { Data($0) })
        data.append(volume)
        data.append(flags)
        data.append(contentsOf: withUnsafeBytes(of: reserved.bigEndian) { Data($0) })
        
        return data
}
    
    /* Deserialization */
    
    static func from(_ data: Data) -> AirCastExtension? {
        guard data.count >= 8
        else {
            return nil
        }
        
        guard let codec = AudioCodec(rawValue: data[0])
        else{
            return nil
        }
        
        let channels = data[1]
        let sampleRate = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        let volume = data[4]
        let flags = data[5]
        let reserved = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        return AirCastExtension(
            codec: codec,
            channels: channels,
            sampleRate: sampleRate,
            volume: volume,
            flags: flags,
            reserved: reserved
        )
    }
}

/* Full AirCast packet: RTP header + AirCast Header + Audio Payload */

struct AudioPacket {
    let rtpHeader: RTPHeader
    let ACextension: AirCastExtension
    let payload: Data

    var size: Int {
        return 12 + 8 + payload.count  /* RTP(12) + Extension(8) + Payload */
    }

    var isEndOfStream: Bool {
        return (ACextension.flags & AirCastExtension.Flags.endOfStream) != 0
    }
    
    init(rtpHeader: RTPHeader, ACextension: AirCastExtension, payload: Data) {
        self.rtpHeader = rtpHeader
        self.ACextension = `ACextension`
        self.payload = payload
    }
    
/* Packet with defaults */
    static func create(
        seqNumber: UInt16,
        timestamp: UInt32,
        ssrc: UInt32,
        codec: AudioCodec,
        channels: UInt8,
        sampleRate: UInt16,
        volume: UInt8,
        payload: Data,
        marker: Bool = false
    ) -> AudioPacket {
        
        let header = RTPHeader(
            payloadType: codec.rawValue,
            seqNumber: seqNumber,
            timestamp: timestamp,
            ssrc: ssrc
        )
        
        let ext = AirCastExtension(
            codec: codec,
            channels: channels,
            sampleRate: sampleRate,
            volume: volume
        )
        
        return AudioPacket(rtpHeader: header, ACextension: ext, payload: payload)
    }
    
/* Serialization */
    func toData() -> Data {
        var data = Data()
        
        data.append(rtpHeader.toData())
        
        data.append(ACextension.toData())
        
        data.append(payload)
        
        return data
    }
    
/* Deserialization */
    static func from(_ data: Data) -> AudioPacket? {
        guard data.count >= 20
        else{
            return nil
        }
        
        guard let rtpHeader = RTPHeader.from(data)
        else {
            return nil
        }
        
        let extData = data.subdata(in: 12..<20)
        guard let ext = AirCastExtension.from(extData)
        else {
            return nil
        }
        
        let payload = data.subdata(in: 20..<data.count)
        
        return AudioPacket(rtpHeader: rtpHeader, ACextension: ext, payload: payload)
    }
}

/* Class to build audio packets with automatic sequence/timestamp tracking */
class AudioPacketBuilder {

    private let ssrc: UInt32 //stream id
    
    private var seqNumber: UInt16 = 0
    private var timestamp: UInt32 = 0
    
    // Audio format
    private let codec: AudioCodec
    private let channels: UInt8
    private let sampleRate: UInt16
    
    // Playback settings
    private var volume: UInt8 = 83
    
    init(codec: AudioCodec, channels: UInt8, sampleRate: UInt16) {
        self.ssrc = UInt32.random(in: 0...UInt32.max)
        
        self.codec = codec
        self.channels = channels
        self.sampleRate = sampleRate
        
        print("Packet builder initialized")
        print("SSRC: \(ssrc)")
        print("Codec: \(codec.name)")
        print("Sample Rate: \(sampleRate) Hz")
    }
    
    /* Build next packet with audio data, takes in encoded audio data and returns complete audio packet ready to send */
    
    func buildPacket(audioData: Data, samplesInPacket: UInt32) -> AudioPacket {
        /* Packet creation */
         let packet = AudioPacket.create(
            seqNumber: seqNumber,
            timestamp: timestamp,
            ssrc: ssrc,
            codec: codec,
            channels: channels,
            sampleRate: sampleRate,
            volume: volume,
            payload: audioData
        )
        
        // Update for next packet
        seqNumber = seqNumber &+ 1  // to prevent overflow crash - basically seqNumber resets to 0 once it hits INT_MAX
        timestamp = timestamp &+ samplesInPacket
        
        return packet
    }

    func buildSyncPacket() -> AudioPacket {
        var flags: UInt8 = 0
        flags |= AirCastExtension.Flags.sync
        
        let header = RTPHeader(
            marker: true,  // Marker for sync packets
            payloadType: codec.rawValue,
            seqNumber: seqNumber,
            timestamp: timestamp,
            ssrc: ssrc
        )
        
        let ext = AirCastExtension(
            codec: codec,
            channels: channels,
            sampleRate: sampleRate,
            volume: volume,
            flags: flags
        )
        
        seqNumber = seqNumber &+ 1
        
        return AudioPacket(rtpHeader: header, ACextension: ext, payload: Data())
    }
    
    /* end-of-stream packet */

    func buildEndPacket() -> AudioPacket {
        var flags: UInt8 = 0
        flags |= AirCastExtension.Flags.endOfStream
        
        let header = RTPHeader(
            marker: true,
            payloadType: codec.rawValue,
            seqNumber: seqNumber,
            timestamp: timestamp,
            ssrc: ssrc
        )
        
        let ext = AirCastExtension(
            codec: codec,
            channels: channels,
            sampleRate: sampleRate,
            volume: volume,
            flags: flags
        )
        
        return AudioPacket(rtpHeader: header, ACextension: ext, payload: Data())
    }
    
    /* Volume for future packets */
    func setVolume(_ newVolume: UInt8) {
        volume = min(newVolume, 100)  // Cap at 100
    }
    
    /* Reset seq number and timestamp */
    func reset() {
        seqNumber = 0
        timestamp = 0
    }
}

