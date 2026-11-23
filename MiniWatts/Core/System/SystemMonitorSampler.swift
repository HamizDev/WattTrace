import Combine
import Darwin
import Foundation
import QuartzCore
import UIKit

/// Foreground-only performance sampling. No private IOKit/HID calls.
/// CPU is for this *process*, not the whole device. 100% means one full
/// logical core; a multithreaded process can exceed 100%.
/// FPS is the observed CADisplayLink callback rate for this app, not a
/// hardware panel-register reading or the FPS of another application.
@MainActor
final class SystemMonitorSampler: NSObject, ObservableObject {
    @Published private(set) var appCPUPercent: Double?
    @Published private(set) var userCPUPercent: Double?
    @Published private(set) var kernelCPUPercent: Double?
    @Published private(set) var displayLinkFPS: Double?
    @Published private(set) var displayMaximumFPS = 0
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private struct CPUReading {
        let uptime: TimeInterval
        let userSeconds: Double
        let systemSeconds: Double
    }

    private var previousCPU: CPUReading?
    private var displayLink: CADisplayLink?
    private var sampleTimer: Timer?
    private var frameWindowStart: CFTimeInterval?
    private var frameCount = 0

    func start() {
        guard displayLink == nil, sampleTimer == nil else { return }
        appCPUPercent = nil
        userCPUPercent = nil
        kernelCPUPercent = nil
        displayLinkFPS = nil
        previousCPU = Self.readCPU()
        thermalState = ProcessInfo.processInfo.thermalState
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        displayMaximumFPS = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
            .max() ?? 0

        frameWindowStart = nil
        frameCount = 0
        let link = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        let timer = Timer(timeInterval: 1,
                          target: self,
                          selector: #selector(onSampleTimer(_:)),
                          userInfo: nil,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        sampleTimer?.invalidate()
        sampleTimer = nil
        previousCPU = nil
        frameWindowStart = nil
        frameCount = 0
        displayLinkFPS = nil
        appCPUPercent = nil
        userCPUPercent = nil
        kernelCPUPercent = nil
    }

    @objc private func onSampleTimer(_ timer: Timer) {
        thermalState = ProcessInfo.processInfo.thermalState
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let current = Self.readCPU() else {
            previousCPU = nil
            appCPUPercent = nil
            userCPUPercent = nil
            kernelCPUPercent = nil
            return
        }
        defer { previousCPU = current }
        guard let previousCPU else { return }
        let elapsed = current.uptime - previousCPU.uptime
        guard elapsed > 0 else { return }

        let user = max(0, current.userSeconds - previousCPU.userSeconds) / elapsed * 100
        let system = max(0, current.systemSeconds - previousCPU.systemSeconds) / elapsed * 100
        userCPUPercent = user
        kernelCPUPercent = system
        appCPUPercent = user + system
    }

    @objc private func onDisplayLink(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        guard let start = frameWindowStart else {
            frameWindowStart = timestamp
            frameCount = 0
            return
        }
        frameCount += 1
        let elapsed = timestamp - start
        guard elapsed >= 0.75 else { return }

        // Count callbacks over a measured wall-time window. This reflects how
        // often *this app* receives display callbacks while this view is active.
        displayLinkFPS = Double(frameCount) / elapsed
        frameWindowStart = timestamp
        frameCount = 0
    }

    private static func readCPU() -> CPUReading? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return CPUReading(uptime: ProcessInfo.processInfo.systemUptime,
                          userSeconds: user,
                          systemSeconds: system)
    }
}
