//
//  NetworkDiscovery.swift
//  AirCast
//
//  Created by Janavi Bathala Vijayabhaskar on 11/6/25.
//

/* Network Discovery - Bonjour(mDNS)
 
  Service Type Format: _service._protocol.domain
  For AirCast: _aircast._tcp.local.
  For AirPrint: _ipp._tcp.local.
 */

import Foundation
import Network
import Combine

/* Represents info about a discovered AirCast receiver */
struct AirCastDevice: Identifiable, Hashable {
    // Identifiable protocol requirement - needed for SwiftUI lists
    let id = UUID()  // Unique ID for each device
    
    // device information
    let name: String            // "Janavi's iPhone"
    let hostname: String        // "iphone.local"
    let ipAddress: String       // "192.168.1.100"
    let port: Int              // 7000
    
    // Device capabilities (from TXT record)
    var supportedCodecs: [String] = []    // ["AAC", "PCM", "ALAC"]
    var channels: Int = 2                  // Stereo
    var sampleRates: [Int] = [44100]       // Supported sample rates
    var features: [String] = []            // ["sync", "eq", "effects"]
    
    // Connection status
    var isAvailable: Bool = true
    var lastSeen: Date = Date()
    
    // Hashable protocol requirement - allows device to be in Sets
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable protocol requirement (part of Hashable)
    static func == (lhs: AirCastDevice, rhs: AirCastDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/* Discover AirCast receivers on the local network - used by Sender to find available receivers */

class AirCastServiceBrowser: NSObject, ObservableObject {
    // @Published means SwiftUI views automatically update when these change
    @Published var discoveredDevices: [AirCastDevice] = []
    @Published var isScanning = false
    
    // NetServiceBrowser - Apple's API for mDNS discovery
    private var browser: NetServiceBrowser?
    
    // Keep track of services being resolved
    // Dictionary maps service name to NetService object
    private var resolvingServices: [String: NetService] = [:]
    
    // The service type we're looking for _aircast = service name, _tcp = protocol (TCP, not UDP for discovery), . = local domain
    private let serviceType = "_aircast._tcp."
    private let domain = "local."
    
    override init() {
        super.init()
        print("AirCast Service Browser initialized")
    }
    
    deinit {
        stopScanning()
        print("AirCast Service Browser deallocated")
    }
    
    /* Scan AirCasr receivers */
    func startScanning() {
        print("Starting scan for AirCast receivers...")
        
        /* Stop existing scans */
        stopScanning()
        
        // Create and configure browser
        browser = NetServiceBrowser()
        browser?.delegate = self
        
        // Start searching for _aircast._tcp.local. services
        browser?.searchForServices(ofType: serviceType, inDomain: domain)
        
        isScanning = true
    }
    
    /* Stop scanning */
    func stopScanning() {
        guard isScanning else { return }
        
        print("Stopping scan...")
        browser?.stop()
        browser = nil
        isScanning = false
    }
    
    // Manually refresh device list
    func refresh() {
        print("Refreshing device list...")
        discoveredDevices.removeAll()
        stopScanning()
        startScanning()
    }
}

extension AirCastServiceBrowser: NetServiceBrowserDelegate {
    // Called when browser starts searching
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("Browser will search")
    }
    
    // Called when a new service is found
    func netServiceBrowser(_ browser: NetServiceBrowser,
                          didFind service: NetService,
                          moreComing: Bool) {
        print("Found service: \(service.name)")
        
        // Set ourselves as delegate to receive resolution events
        service.delegate = self
        
        // Store service for tracking
        resolvingServices[service.name] = service
        
        // Resolve the service to get IP address and port
        // Timeout after 5 seconds
        service.resolve(withTimeout: 5.0)
        
        // moreComing indicates if more services are being reported
        // If false, this is the last one (for now)
        if !moreComing {
            print("No more services coming")
        }
    }
    
    // Called when a service is removed (device goes offline)
    func netServiceBrowser(_ browser: NetServiceBrowser,
                          didRemove service: NetService,
                          moreComing: Bool) {
        print("Removed service: \(service.name)")
        
        // Remove from our list
        discoveredDevices.removeAll { $0.name == service.name }
        resolvingServices.removeValue(forKey: service.name)
    }
    
    // Called if search fails
    func netServiceBrowser(_ browser: NetServiceBrowser,
                          didNotSearch errorDict: [String: NSNumber]) {
        print("Browser search failed: \(errorDict)")
        isScanning = false
    }
}

extension AirCastServiceBrowser: NetServiceDelegate {
    // Called when service resolution succeeds
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("Resolved service: \(sender.name)")
        
        // Extract hostname (e.g., "iphone.local")
        guard let hostname = sender.hostName else {
            print("No hostname for service")
            return
        }
        
        // Extract IP address from address data
        guard let ipAddress = extractIPAddress(from: sender) else {
            print("Could not extract IP address")
            return
        }
        
        // Parse TXT record for capabilities
        let capabilities = parseTXTRecord(sender.txtRecordData())
        
        // Create device object
        let device = AirCastDevice(
            name: sender.name,
            hostname: hostname,
            ipAddress: ipAddress,
            port: sender.port,
            supportedCodecs: capabilities["codecs"] ?? ["AAC"],
            channels: Int(capabilities["channels"]?.first ?? "2") ?? 2,
            sampleRates: parseSampleRates(capabilities["samplerate"]?.first ?? "44100"),
            features: capabilities["features"] ?? []
        )
        
        // Add to discovered devices if not already present
        if !discoveredDevices.contains(where: { $0.name == device.name }) {
            discoveredDevices.append(device)
            print("Added device: \(device.name) at \(device.ipAddress):\(device.port)")
        }
        
        // Clean up
        resolvingServices.removeValue(forKey: sender.name)
    }
    
    // Called if resolution fails
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("Failed to resolve service: \(sender.name) - \(errorDict)")
        resolvingServices.removeValue(forKey: sender.name)
    }
}

extension AirCastServiceBrowser {
    // Extract IP address from NetService address data
    private func extractIPAddress(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        
        for addressData in addresses {
            let data = addressData as Data
            var storage = sockaddr_storage()
            
            // Copy address data into sockaddr_storage
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                memcpy(&storage, baseAddress, min(MemoryLayout<sockaddr_storage>.size, data.count))
            }
            
            // Check if IPv4
            if storage.ss_family == sa_family_t(AF_INET) {
                // Cast to sockaddr_in (IPv4 structure)
                var addr = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                }
                
                // Convert binary address to string
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buffer)
            }
            
            // Check if IPv6
            if storage.ss_family == sa_family_t(AF_INET6) {
                var addr = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                }
                
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &addr.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                return String(cString: buffer)
            }
        }
        
        return nil
    }
    
    // Parse TXT record (key-value pairs)
    // TXT records contain device capabilities
    private func parseTXTRecord(_ data: Data?) -> [String: [String]] {
        guard let data = data else { return [:] }
        
        // NetService provides a method to parse TXT record
        let dict = NetService.dictionary(fromTXTRecord: data)
        
        var result: [String: [String]] = [:]
        
        for (key, value) in dict {
            if let stringValue = String(data: value, encoding: .utf8) {
                // Split comma-separated values
                let values = stringValue.components(separatedBy: ",")
                result[key] = values
            }
        }
        
        return result
    }
    
    // Parse sample rates from string like "44100,48000"
    private func parseSampleRates(_ string: String) -> [Int] {
        return string.components(separatedBy: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

// Advertises this device as an AirCast receiver
// This is what the RECEIVER uses to announce itself
class AirCastServiceAdvertiser: NSObject {
    private var service: NetService?
    
    private let serviceType = "_aircast._tcp."
    private let domain = "local."
    
    // Device information
    private let deviceName: String
    private let port: Int
    private let capabilities: [String: String]
   
    // Create advertiser

    init(deviceName: String, port: Int, capabilities: [String: String] = [:]) {
        self.deviceName = deviceName // device name to be advertised "Janavi's iPhone"
        self.port = port // listening port
        self.capabilities = capabilities // device capabilities for TXT records
        super.init()
    }
    
    deinit {
        stopAdvertising()
    }
    
   func startAdvertising() {
        print("Starting to advertise as '\(deviceName)'")
        
        // Stop any currently existing service
        stopAdvertising()
        
        // Create NetService
        service = NetService(domain: domain,
                            type: serviceType,
                            name: deviceName,
                            port: Int32(port))
        
        service?.delegate = self
        
        // Set TXT record with capabilities
        let txtRecord = createTXTRecord()
        service?.setTXTRecord(txtRecord)
        
        // Publish on all network interfaces
        service?.publish()
        
        print("Advertising on port \(port)")
    }
    
    
    func stopAdvertising() {
        service?.stop()
        service = nil
        print("Stopped advertising")
    }
    
    // Create TXT record with device capabilities
    private func createTXTRecord() -> Data {
        // Default capabilities
        var record = capabilities
        
        // Add version if not present
        if record["txtvers"] == nil {
            record["txtvers"] = "1"
        }
        
        // Convert to Data
        // NetService.data method converts [String: String] to TXT record format
 //       return NetService.data(fromTXTRecord: record as [String: Data])
        return NetService.data(fromTXTRecord: record.compactMapValues { $0.data(using: .utf8) })
    }
}

extension AirCastServiceAdvertiser: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("Service published successfully: \(sender.name)")
        print("Type: \(sender.type)")
        print("Domain: \(sender.domain)")
        print("Port: \(sender.port)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("Failed to publish service: \(errorDict)")
    }
    
    func netServiceWillPublish(_ sender: NetService) {
        print("Service will publish: \(sender.name)")
    }
    
    func netServiceDidStop(_ sender: NetService) {
        print("Service stopped: \(sender.name)")
    }
}

