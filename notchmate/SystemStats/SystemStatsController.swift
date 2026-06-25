import Combine
import Foundation

/// A point-in-time CPU + memory reading, each normalised to 0...1.
struct SystemSample: Equatable {
    let cpu: Double      // fraction of total CPU busy since last sample
    let memUsed: Double  // fraction of physical RAM in use
}

/// Polls system-wide CPU and memory load via Mach host statistics (no third-party dep)
/// and publishes to main on a ~2s interval. CPU is a delta between samples (the kernel
/// reports cumulative ticks), so the first reading is 0 until a baseline exists. All
/// failures degrade to zeroes - never throws.
final class SystemStatsController: ObservableObject {
    @Published private(set) var sample = SystemSample(cpu: 0, memUsed: 0)

    /// CPU is "high" enough to surface in the collapsed strip.
    static let cpuHighThreshold = 0.70
    var cpuHigh: Bool { sample.cpu >= Self.cpuHighThreshold }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchmate.sysstats.scan")
    private var prevCPU: (used: Double, total: Double)?  // queue-only

    func start() {
        scan()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    private func scan() {
        queue.async { [weak self] in
            guard let self else { return }
            let s = SystemSample(cpu: self.readCPU(), memUsed: SystemStatsController.readMem())
            DispatchQueue.main.async { if s != self.sample { self.sample = s } }
        }
    }

    // MARK: - Mach readings (queue-only)

    /// Total CPU busy fraction since the previous sample. Returns 0 until a baseline.
    private func readCPU() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        // cpu_ticks order: user, system, idle, nice.
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        defer { prevCPU = (used, total) }

        guard let prev = prevCPU else { return 0 }
        let dUsed = used - prev.used
        let dTotal = total - prev.total
        guard dTotal > 0 else { return 0 }
        return min(1, max(0, dUsed / dTotal))
    }

    /// Fraction of physical RAM in use (active + wired + compressed).
    private static func readMem() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_page_size)
        let active = Double(stats.active_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        let used = (active + wired + compressed) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(1, max(0, used / total))
    }
}
