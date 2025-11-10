//
//  ContentView.swift
//  AirCast
//
//  Created by Janavi Bathala Vijayabhaskar on 11/6/25.
//

import SwiftUI
import Combine

class StreamingManager: ObservableObject {
    @Published var isStreaming = false
    @Published var packetsSent = 0
    
    private var sender: UDPAudioSender?
    private var streamTimer: Timer?
    private var builder: AudioPacketBuilder?
    
    func startStreaming(to device: AirCastDevice) {
        print("Starting stream to \(device.name)")
        
        let s = UDPAudioSender(host: device.ipAddress, port: device.port)
        sender = s
        
        s.onStateChange = { [weak self] state in
            if case .connected = state {
                DispatchQueue.main.async {
                    print("Connected!")
                    self?.isStreaming = true
                    self?.sendTestPackets()
                }
            } else if case .failed(let error) = state {
                print("Connection failed: \(error)")
            }
        }
        
        s.connect()
    }
    
    func stopStreaming() {
        streamTimer?.invalidate()
        streamTimer = nil
        sender?.disconnect()
        sender = nil
        isStreaming = false
        packetsSent = 0
        builder = nil
    }
    
    private func sendTestPackets() {
        let b = AudioPacketBuilder(codec: .aac, channels: 2, sampleRate: 44100)
        builder = b
        
        streamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            
            var fakeAudio = Data()
            for i in 0..<1024 {
                let value = UInt8((sin(Double(self.packetsSent + i) * 0.1) * 127) + 128)
                fakeAudio.append(value)
            }
            
            let packet = b.buildPacket(audioData: fakeAudio, samplesInPacket: 1024)
            self.sender?.send(packet: packet)
            
            DispatchQueue.main.async {
                self.packetsSent += 1
            }
        }
    }
}

class ReceiverManager: ObservableObject {
    @Published var isListening = false
    @Published var packetsReceived = 0
    @Published var currentSender = "None"
    @Published var lastPacketTime = Date()
    
    private var advertiser: AirCastServiceAdvertiser?
    private var receiver: UDPAudioReceiver?
    
    let deviceName = UIDevice.current.name
    let port = 7000
    
    func startAdvertising() {
        let adv = AirCastServiceAdvertiser(
            deviceName: deviceName,
            port: port,
            capabilities: [
                "txtvers": "1",
                "codecs": "AAC,PCM",
                "channels": "2",
                "samplerate": "44100,48000",
                "features": "basic"
            ]
        )
        
        adv.startAdvertising()
        advertiser = adv
        print("Advertising as: \(deviceName)")
    }
    
    func stopAdvertising() {
        advertiser?.stopAdvertising()
        advertiser = nil
    }
    
    func startReceiving() {
        let recv = UDPAudioReceiver(port: port)
        receiver = recv
        
        recv.onPacketReceived = { [weak self] packet in
            DispatchQueue.main.async {
                self?.packetsReceived += 1
                self?.lastPacketTime = Date()
            }
            
            if let count = self?.packetsReceived, count % 50 == 0 {
                print("Received \(count) packets")
            }
        }
        
        recv.onConnectionReceived = { [weak self] sender in
            DispatchQueue.main.async {
                self?.currentSender = sender
                print("Connection from: \(sender)")
            }
        }
        
        recv.onError = { error in
            print("Receiver error: \(error)")
        }
        
        do {
            try recv.startListening()
            isListening = true
            print("Listening on port \(port)")
        } catch {
            print("Failed to start listening: \(error)")
        }
    }
    
    func stopReceiving() {
        receiver?.stopListening()
        receiver = nil
        isListening = false
        packetsReceived = 0
        currentSender = "None"
    }
}

struct ContentView: View {
    @State private var selectedMode = 0  // 0 = Sender, 1 = Receiver
    
    // TBD: Earlier, I was losing state. These persist across tab switches.
    @StateObject private var browser = AirCastServiceBrowser()
    @StateObject private var streamingManager = StreamingManager()
    @StateObject private var receiverManager = ReceiverManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("AirCast")
                    .font(.largeTitle)
                    .bold()
                
                Picker("Mode", selection: $selectedMode) {
                    Text("Sender").tag(0)
                    Text("Receiver").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedMode == 1 {
                   ReceiverView(manager: receiverManager)
                } else {
                    SenderView(browser: browser, streamingManager: streamingManager)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct SenderView: View {
    @ObservedObject var browser: AirCastServiceBrowser
    @ObservedObject var streamingManager: StreamingManager
    @State private var selectedDevice: AirCastDevice?
    
    var body: some View {
        VStack {
            HStack {
                Button(browser.isScanning ? "Stop Scanning" : "Start Scanning") {
                    if browser.isScanning {
                        browser.stopScanning()
                    } else {
                        browser.startScanning()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Text("\(browser.discoveredDevices.count) devices")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            if browser.discoveredDevices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No devices found")
                        .font(.headline)
                    
                    Text(browser.isScanning ? "Scanning..." : "Tap 'Start Scanning' to find receivers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(browser.discoveredDevices) { device in
                    DeviceRow(device: device, isSelected: selectedDevice?.id == device.id)
                        .onTapGesture {
                            selectedDevice = device
                        }
                }
            }
            
            if let device = selectedDevice {
                VStack(spacing: 10) {
                    Text("Selected: \(device.name)")
                        .font(.headline)
                    
                    Text("\(device.ipAddress):\(device.port)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button(streamingManager.isStreaming ? "Stop Streaming" : "Start Test Stream") {
                            if streamingManager.isStreaming {
                                streamingManager.stopStreaming()
                            } else {
                                streamingManager.startStreaming(to: device)                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(streamingManager.isStreaming ? .red : .blue)
                        if streamingManager.isStreaming {
                            Text("\(streamingManager.packetsSent) packets sent")
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding()
            }
        }
    }

    
}

struct ReceiverView: View {
    @ObservedObject var manager: ReceiverManager
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: manager.isListening ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                    .font(.system(size: 50))
                    .foregroundColor(manager.isListening ? .blue : .secondary)
                
                Text(manager.isListening ? "Listening for connections..." : "Not listening")
                    .font(.headline)
                
                Text("Device: \(manager.deviceName)")
                    .font(.caption)
                
                Text("Port: \(manager.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Button(manager.isListening ? "Stop Receiving" : "Start Receiving") {
                if manager.isListening {
                    manager.stopReceiving()
                } else {
                    manager.startAdvertising()
                    manager.startReceiving()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isListening ? .red : .green)
            
            if manager.isListening {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Statistics")
                        .font(.headline)
                    
                    HStack {
                        Text("Packets received:")
                        Spacer()
                        Text("\(manager.packetsReceived)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Sender:")
                        Spacer()
                        Text(manager.currentSender)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Last packet:")
                        Spacer()
                        Text(timeAgo(manager.lastPacketTime))
                            .fontWeight(.semibold)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding()
            }
            
            Spacer()
        }
    }
    
    func timeAgo(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 1 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        return "\(Int(seconds / 60))m ago"
    }
    
}

struct DeviceRow: View {
    let device: AirCastDevice
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                
                Text("\(device.ipAddress):\(device.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Codecs: \(device.supportedCodecs.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
