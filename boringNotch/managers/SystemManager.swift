//
//  SystemManager.swift
//  boringNotch
//
//  Spike: minimal native system monitor (CPU/RAM/GPU/network/disk/wifi) —
//  a "short btop" for a notch tab. CPU/RAM/network/disk use native
//  Mach/BSD APIs (no subprocess); GPU reads the same IOAccelerator
//  performance-statistics node the `stats`/iStat-style tools use.
//

import Foundation
import Darwin
import Combine
#if canImport(CoreWLAN)
import CoreWLAN
#endif

struct SystemSample: Equatable {
    var cpuPercent: Double = 0
    var memPercent: Double = 0
    var gpuPercent: Double = 0
    var netUpBytesPerSec: Double = 0
    var netDownBytesPerSec: Double = 0
    var diskUsedFraction: Double = 0
    var diskFreeGB: Double = 0
    var diskTotalGB: Double = 0
    var wifiSSID: String?
    var hostname: String = ""
}

@MainActor
final class SystemManager: ObservableObject {
    static let shared = SystemManager()

    @Published private(set) var current = SystemSample()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var netHistory: [Double] = []

    private let historyLimit = 40
    private var timer: Timer?

    private var previousCPUTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var previousNetBytes: (in: UInt64, out: UInt64, at: Date)?

    private init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func sample() {
        Task.detached(priority: .utility) {
            let cpu = Self.readCPU()
            let mem = Self.readMemory()
            let gpu = Self.readGPU()
            let disk = Self.readDisk()
            let hostname = ProcessInfo.processInfo.hostName
            let ssid = Self.readWiFiSSID()

            await MainActor.run { [weak self] in
                guard let self else { return }

                let cpuPercent = self.deltaCPU(cpu)
                let (netUp, netDown) = self.deltaNet()

                self.current = SystemSample(
                    cpuPercent: cpuPercent,
                    memPercent: mem,
                    gpuPercent: gpu,
                    netUpBytesPerSec: netUp,
                    netDownBytesPerSec: netDown,
                    diskUsedFraction: disk.total > 0 ? 1 - (disk.free / disk.total) : 0,
                    diskFreeGB: disk.free / 1_000_000_000,
                    diskTotalGB: disk.total / 1_000_000_000,
                    wifiSSID: ssid,
                    hostname: hostname
                )

                Self.push(&self.cpuHistory, cpuPercent, limit: self.historyLimit)
                Self.push(&self.memHistory, mem, limit: self.historyLimit)
                Self.push(&self.gpuHistory, gpu, limit: self.historyLimit)
                Self.push(&self.netHistory, netUp + netDown, limit: self.historyLimit)
            }
        }
    }

    private static func push(_ array: inout [Double], _ value: Double, limit: Int) {
        array.append(value)
        if array.count > limit {
            array.removeFirst(array.count - limit)
        }
    }

    // MARK: - CPU (host_processor_info, delta of cumulative ticks)

    private nonisolated static func readCPU() -> [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(numCpuInfo) * MemoryLayout<Int32>.size))
        }

        var ticks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        for i in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])
            ticks.append((user, system, idle, nice))
        }
        return ticks
    }

    private func deltaCPU(_ current: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)]) -> Double {
        defer { previousCPUTicks = current }
        guard previousCPUTicks.count == current.count, !current.isEmpty else { return 0 }

        var totalUsed: Double = 0
        var totalTicks: Double = 0
        for i in 0..<current.count {
            let prev = previousCPUTicks[i]
            let now = current[i]
            let user = Double(now.user &- prev.user)
            let system = Double(now.system &- prev.system)
            let idle = Double(now.idle &- prev.idle)
            let nice = Double(now.nice &- prev.nice)
            let used = user + system + nice
            let total = used + idle
            totalUsed += used
            totalTicks += total
        }
        guard totalTicks > 0 else { return 0 }
        return min(100, max(0, (totalUsed / totalTicks) * 100))
    }

    // MARK: - Memory (host_statistics64)

    private nonisolated static func readMemory() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        guard totalMem > 0 else { return 0 }
        return min(100, max(0, (used / Double(totalMem)) * 100))
    }

    // MARK: - GPU (IOAccelerator performance statistics)

    private nonisolated static func readGPU() -> Double {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-r", "-d", "1", "-c", "IOAccelerator"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return 0 }

        guard let range = output.range(of: "\"Device Utilization %\"=") else { return 0 }
        let tail = output[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Double(digits) ?? 0
    }

    // MARK: - Disk (statfs on root volume)

    private nonisolated static func readDisk() -> (free: Double, total: Double) {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return (0, 0) }
        let free = Double(stat.f_bfree) * Double(stat.f_bsize)
        let total = Double(stat.f_blocks) * Double(stat.f_bsize)
        return (free, total)
    }

    // MARK: - Network (getifaddrs, delta of cumulative byte counters)

    private nonisolated static func readNetBytes() -> (in: UInt64, out: UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            let name = String(cString: p.pointee.ifa_name)
            if (flags & IFF_UP) != 0, name.hasPrefix("en"),
               let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = p.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                bytesIn += UInt64(networkData.ifi_ibytes)
                bytesOut += UInt64(networkData.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        return (bytesIn, bytesOut)
    }

    private func deltaNet() -> (up: Double, down: Double) {
        let now = Date()
        let bytes = Self.readNetBytes()
        defer { previousNetBytes = (bytes.in, bytes.out, now) }

        guard let prev = previousNetBytes else { return (0, 0) }
        let elapsed = now.timeIntervalSince(prev.at)
        guard elapsed > 0 else { return (0, 0) }

        let downDelta = bytes.in >= prev.in ? Double(bytes.in - prev.in) : 0
        let upDelta = bytes.out >= prev.out ? Double(bytes.out - prev.out) : 0
        return (upDelta / elapsed, downDelta / elapsed)
    }

    // MARK: - WiFi SSID

    private nonisolated static func readWiFiSSID() -> String? {
        #if canImport(CoreWLAN)
        return CWWiFiClient.shared().interface()?.ssid()
        #else
        return nil
        #endif
    }
}
