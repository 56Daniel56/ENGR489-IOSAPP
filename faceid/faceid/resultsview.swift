//
//  ResultsView.swift
//  faceid
//
//  Created by Daniel Herbert on 18/07/2025.
//

import SwiftUI

class AppState: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var sessionId: String?
    @Published var callback: String?
    @Published var shouldShowVerification = false
}

struct resultsview: View {
    @EnvironmentObject var appState: AppState
    
    let match: String?
    let message: [String]?
    let name: String?
    let dob: String?
    
    // MARK: - Computed Properties

    private var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        return "User"
    }

    private var displayDOB: String {
        if let dob = dob, !dob.isEmpty {
            return dob
        }
        return "Not available"
    }
    
    private var isMatchSuccessful: Bool {
        match?.lowercased().contains("faces match") == true
    }

    // MARK: - View

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - Header Section
                VStack(spacing: 12) {
                    Image(systemName: isMatchSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(isMatchSuccessful ? .green : .red)
                    
                    Text("Hello, \(displayName)!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(isMatchSuccessful
                         ? "Identity Verification Complete"
                         : "Identity Verification Failed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // MARK: - Match Status Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "person.badge.shield.checkmark")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("Verification Status")
                            .font(.headline)
                        Spacer()
                    }

                    HStack {
                        Text("Match Result:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(match ?? "Unknown")
                            .fontWeight(.bold)
                            .foregroundColor(isMatchSuccessful ? .green : .primary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personal Information")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Full Name:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(displayName)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Date of Birth:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(displayDOB)
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding(20)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // MARK: - Additional Information Card
                if let messages = message, !messages.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Text("Verification Details")
                                .font(.headline)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                                HStack(alignment: .top) {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(msg)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // MARK: - Callback / Redirect Info
                if let callback = appState.callback {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Text("Return Destination")
                                .font(.headline)
                            Spacer()
                        }

                        Text(callback)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                // MARK: - Confirm Button
                Button(action: {
                    guard let match = match,
                          let sessionId = appState.sessionId,
                          let callback = appState.callback,
                          let messages = message,
                          messages.count >= 2 else {
                        print("Missing required values for network call")
                        return
                    }

                    NetworkManager.shared.prepareappatest(
                        message: match,
                        id: sessionId,
                        fulName: messages[0],
                        birth: messages[1]
                    )

                    if let url = URL(string: callback) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Confirm & Continue")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarHidden(true)
        .background(Color(.systemBackground))
    }
}
