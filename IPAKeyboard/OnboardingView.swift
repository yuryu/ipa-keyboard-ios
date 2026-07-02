//
//  OnboardingView.swift
//  IPAKeyboard
//
//  First-run / on-demand guidance for enabling the keyboard in Settings
//  (issue #7). Auto-presented once on first launch (state in
//  `OnboardingState`) and reopenable anytime from the layout list's help
//  button. Deliberately states that Full Access is NOT required — the
//  keyboard types without it and nothing here should push users to grant it.
//
//  The "Open Settings" button deep-links via
//  `UIApplication.openSettingsURLString`, which opens this app's page in
//  Settings; once the keyboard extension is installed, a "Keyboards" item
//  appears there. If the open fails, an inline fallback message points the
//  user at the manual steps (which are always on screen anyway).
//
//  Accessibility identifier scheme (for ui-test-author):
//    onboarding-view                 — the sheet's root scroll view
//    onboarding-full-access-note     — the "Full Access not required" callout
//    onboarding-open-settings-button — the Settings deep-link button
//    onboarding-settings-open-failed — inline fallback when the deep link fails
//    onboarding-done-button          — the Done toolbar button
//

import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settingsOpenFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    steps
                    fullAccessNote
                    settingsSection
                }
                .padding()
                // Cap the line length so the sheet reads comfortably on iPad,
                // centered within whatever width the sheet gets.
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("onboarding-view")
            .navigationTitle("Enable the Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("onboarding-done-button")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("IPAKeyboard is a system keyboard. Add it once in the "
                + "Settings app, and it becomes available anywhere you type.")
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingStep(number: 1, text: "Open the Settings app.")
            OnboardingStep(
                number: 2,
                text: "Go to General, then Keyboard, then Keyboards."
            )
            OnboardingStep(
                number: 3,
                text: "Tap “Add New Keyboard…” and choose IPAKeyboard."
            )
            OnboardingStep(
                number: 4,
                text: "When typing, touch and hold the globe key to switch "
                    + "to IPAKeyboard."
            )
        }
    }

    private var fullAccessNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Full Access is not required")
                    .font(.headline)
                Text("IPAKeyboard types phonetic symbols without any special "
                    + "permissions. You can leave “Allow Full Access” turned "
                    + "off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-full-access-note")
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding-open-settings-button")

            Text("Opens IPAKeyboard’s page in Settings. After the keyboard "
                + "is added, a “Keyboards” option appears there too.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if settingsOpenFailed {
                Label(
                    "Couldn’t open Settings automatically. Open the Settings "
                        + "app yourself and follow the steps above.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("onboarding-settings-open-failed")
            }
        }
    }

    /// Deep-link toward Settings. `openSettingsURLString` opens this app's
    /// settings page; failure flips an inline fallback message instead of
    /// erroring, since the manual steps are always visible.
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsOpenFailed = true
            return
        }
        let failed = $settingsOpenFailed
        UIApplication.shared.open(url) { accepted in
            if !accepted {
                failed.wrappedValue = true
            }
        }
    }
}

/// One numbered instruction row. VoiceOver reads it as a single element:
/// "Step N: …".
private struct OnboardingStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(minWidth: 28, minHeight: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}

#if DEBUG
#Preview {
    OnboardingView()
}
#endif
