import SwiftUI

struct ProcessingView: View {
    let status: AnalysisStatus

    private struct Step: Identifiable, Equatable {
        let id: AnalysisStatus
        let label: String
    }

    private let steps: [Step] = [
        .init(id: .refining, label: "Refining speaker separation…"),
        .init(id: .measuring, label: "Measuring talk time and pace…"),
        .init(id: .detecting, label: "Detecting interruptions and hedges…"),
        .init(id: .building, label: "Building your coaching report…"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Analyzing")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Hold on a moment.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Divider().background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps) { step in
                        ChecklistRow(
                            label: step.label,
                            state: state(for: step.id)
                        )
                    }
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    fileprivate enum RowState { case pending, active, done }

    fileprivate func state(for id: AnalysisStatus) -> RowState {
        switch (id, status) {
        case (.refining, .refining), (.measuring, .measuring), (.detecting, .detecting), (.building, .building):
            return .active
        default:
            break
        }
        let order: [AnalysisStatus] = [.refining, .measuring, .detecting, .building, .complete]
        let stepIdx = order.firstIndex(of: id) ?? 0
        let statusIdx = order.firstIndex(of: status) ?? 0
        return statusIdx > stepIdx ? .done : .pending
    }
}

private struct ChecklistRow: View {
    let label: String
    let state: ProcessingView.RowState

    var body: some View {
        HStack(spacing: 14) {
            Group {
                switch state {
                case .pending:
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.2).frame(width: 18, height: 18)
                case .active:
                    ProgressView().controlSize(.small).tint(AppColor.primary)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.primary)
                        .font(.system(size: 18))
                }
            }
            .frame(width: 24, alignment: .center)

            Text(label)
                .font(.body)
                .foregroundStyle(state == .pending ? .white.opacity(0.4) : .white.opacity(0.95))
        }
        .opacity(state == .pending ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

#Preview {
    ProcessingView(status: .measuring)
}
