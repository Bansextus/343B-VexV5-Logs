import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: TaheraModel
    @State private var pulseLogo = false
    @State private var driftGlow = false
    @State private var hoveredSection: AppSection?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            animatedBackdrop

            HStack(spacing: 0) {
                sidebar

                Divider()
                    .overlay(Color.white.opacity(0.12))

                detailPane
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 1120, minHeight: 720)

            cornerLogo
        }
        .animation(.easeInOut(duration: 0.25), value: model.currentSection)
        .onAppear {
            pulseLogo = true
            driftGlow = true
        }
    }

    private var cornerLogo: some View {
        VStack {
            HStack {
                Spacer()
                Image("tahera_logo", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .opacity(0.88)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 14)
                    .padding(16)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var animatedBackdrop: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 24)
                .offset(x: driftGlow ? -420 : -340, y: driftGlow ? -240 : -170)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: driftGlow)

            Circle()
                .fill(Theme.accentMuted.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 20)
                .offset(x: driftGlow ? 470 : 370, y: driftGlow ? 200 : 120)
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: driftGlow)
        }
        .allowsHitTesting(false)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("tahera_logo", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 78, height: 78)
                    .shadow(color: Theme.accent.opacity(pulseLogo ? 0.55 : 0.25), radius: pulseLogo ? 22 : 10)
                    .scaleEffect(pulseLogo ? 1.04 : 0.96)
                    .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: pulseLogo)

                Text("Tahera")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
            }
            .padding(.bottom, 8)

            ForEach(AppSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        model.currentSection = section
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.symbolName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(model.currentSection == section ? Theme.accent : Theme.subtext.opacity(0.8))
                            .frame(width: 30, height: 30)
                        Text(section.rawValue)
                            .foregroundColor(Theme.text)
                            .font(.system(size: 23, weight: model.currentSection == section ? .bold : .semibold, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(model.currentSection == section ? Color.black.opacity(0.25) : (hoveredSection == section ? Color.white.opacity(0.08) : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(model.currentSection == section ? Theme.accent.opacity(0.9) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: model.currentSection == section ? Theme.accent.opacity(0.25) : Color.clear, radius: 8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredSection = isHovering ? section : (hoveredSection == section ? nil : hoveredSection)
                }
                .animation(.easeInOut(duration: 0.16), value: hoveredSection == section)
            }

            Spacer()

            if model.isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Running command...")
                        .foregroundColor(Theme.subtext)
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .padding(18)
        .frame(width: 344)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.36), Color.black.opacity(0.2)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var detailPane: some View {
        sectionView
            .id(model.currentSection)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity
                )
            )
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Theme.accent.opacity(0.12), Color.clear]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(color: Color.black.opacity(0.42), radius: 18, x: 0, y: 12)
            )
    }

    @ViewBuilder
    private var sectionView: some View {
        switch model.currentSection {
        case .home:
            HomeView()
        case .build:
            BuildUploadView()
        case .controls:
            ControllerMappingView()
        case .portMap:
            PortMapView()
        case .sdCard:
            SDCardView()
        case .field:
            FieldReplayView()
        case .virtualBrain:
            VirtualBrainView(brain: model.virtualBrain)
        case .vexOS:
            VexOSView(brain: model.virtualBrain)
        case .readme:
            ReadmeView()
        case .github:
            GitHubView()
        }
    }
}
