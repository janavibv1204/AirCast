# AirCast - Network Audio Streaming System

**A real-time audio streaming application demonstrating Bonjour/mDNS service discovery and RTP-based UDP streaming, built with Swift and SwiftUI.**

---

## Screenshots

### Sender Mode - Device Discovery
![Sender discovering devices](screenshots/sender.png)

### Receiver Mode
![Receiver receiving audio packets](screenshots/receiver.png)

---

## Overview

AirCast demonstrates core networking concepts used in modern streaming systems:

- **Service Discovery**: Bonjour/mDNS for zero-configuration networking
- **Streaming Protocol**: Custom RTP-based protocol for real-time media
- **Network Transport**: UDP for low-latency streaming
- **Modern UI**: SwiftUI interface

Built to showcase understanding of:
- Binary protocol design and implementation
- Network programming (UDP sockets, multicast DNS)
- Real-time streaming challenges
- Modern iOS/macOS development

---

## Features

### Core Functionality
- **Automatic Device Discovery** - Find receivers using Bonjour/mDNS
- **Real-time Streaming** - UDP-based packet transmission
- **Network Statistics** - Track packets, latency, packet loss
- **Dual Modes** - Single app as sender or receiver
- **Clean Architecture** - Separated network, protocol, and UI layers

### Technical Highlights
- Custom RTP-based packet protocol (RFC 3550)
- Binary serialization with network byte ordering
- Zero-configuration service discovery
- Connection state management
- Packet loss detection via sequence numbers

## Architecture

```
┌─────────────────────────────────────┐
│      Application (SwiftUI)          │
├─────────────────────────────────────┤
│                                     │
│  Discovery (Bonjour/mDNS)           │
│           ↓                         │
│  Transport (UDP)                    │
│           ↓                         │
│  Protocol (RTP)                     │
│                                     │
└─────────────────────────────────────┘
```

**Key Components:**

1. **Service Discovery**
   - Bonjour/mDNS implementation
   - Device advertisement and browsing
   - Capability negotiation

2. **Packet Protocol**
   - RTP-based structure (RFC 3550)
   - Binary serialization
   - Sequence and timestamp management

3. **Network Transport**
   - UDP sender/receiver
   - Connection state management
   - Statistics tracking

4. **User Interface**
   - SwiftUI reactive views
   - Real-time updates
   - Clean, modern design

---

## Technical Details

### Service Discovery Protocol

**mDNS/Bonjour:**
- Service Type: `_aircast._tcp.local`
- Multicast Address: 224.0.0.251:5353
- TXT Records: Device capabilities
- Zero-configuration networking

### Packet Protocol Structure

```
┌────────────────────────────────┐
│ RTP Header (12 bytes)          │
│ - Version (2 bits)             │
│ - Sequence Number (16 bits)    │
│ - Timestamp (32 bits)          │
│ - SSRC (32 bits)               │
├────────────────────────────────┤
│ Custom Extension (8 bytes)     │
│ - Codec ID                     │
│ - Channels                     │
│ - Sample Rate                  │
│ - Control Flags                │
├────────────────────────────────┤
│ Audio Payload (variable)       │
└────────────────────────────────┘
```

### Network Transport

- **Protocol**: UDP (User Datagram Protocol)
- **Port**: 7000 (configurable)
- **Packet Rate**: ~50 packets/second
- **Packet Size**: ~1KB typical
- **QoS**: User-interactive priority

---

## Current Implementation

**What's Working:**
- Device discovery via Bonjour
- UDP packet streaming
- Packet loss detection
- Network statistics
- Dual sender/receiver modes

**Intentional Simplifications:**
- Sends test packets (not real audio files)
- No encryption
- No packet retransmission
- Basic jitter handling
- Single sender per receiver

---

## Future Enhancements

Potential additions for production use:

- Real audio file streaming
- Audio encoding/decoding (AAC, ALAC)
- Jitter buffer implementation
- Multi-device synchronization
- Encryption (AES-128)
- Packet retransmission
- Audio visualization
- Adaptive bitrate control

---

## Technical Resources

**Protocols:**
- [RFC 3550 - RTP: Real-Time Transport Protocol](https://tools.ietf.org/html/rfc3550)
- [RFC 6762 - Multicast DNS](https://tools.ietf.org/html/rfc6762)
- [RFC 6763 - DNS-Based Service Discovery](https://tools.ietf.org/html/rfc6763)

**Apple Documentation:**
- [Network Framework](https://developer.apple.com/documentation/network)
- [Bonjour Overview](https://developer.apple.com/bonjour/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)

---

**⭐ If you find this project helpful, please give it a star!**

---

*Built with ❤️ and Swift*
