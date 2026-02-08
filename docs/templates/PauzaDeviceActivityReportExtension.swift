import DeviceActivity
import SwiftUI

@main
struct PauzaDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        PauzaDailyReportScene()
    }
}

private struct PauzaDailyReport {
    let totalActivityDuration: TimeInterval
}

private struct PauzaDailyReportView: View {
    let report: PauzaDailyReport

    var body: some View {
        VStack(spacing: 8) {
            Text("Screen Time")
                .font(.headline)
            Text(formattedDuration(report.totalActivityDuration))
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0m"
    }
}

private struct PauzaDailyReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init("daily")
    let content: (PauzaDailyReport) -> PauzaDailyReportView = { report in
        PauzaDailyReportView(report: report)
    }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> PauzaDailyReport {
        var totalActivityDuration: TimeInterval = 0

        for await activityData in data {
            for await activitySegment in activityData.activitySegments {
                for await category in activitySegment.categories {
                    for await application in category.applications {
                        totalActivityDuration += application.totalActivityDuration
                    }
                }
            }
        }

        return PauzaDailyReport(totalActivityDuration: totalActivityDuration)
    }
}
