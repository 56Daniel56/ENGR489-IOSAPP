//
//  lockedView.swift
//  faceid
//
//  Created by Daniel Herbert on 01/08/2025.
//
import SwiftUI

struct LockedView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseAnimation = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Professional gradient background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground),
                        Color(.tertiarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Lock Icon with Animation
                    ZStack {
                        // Outer pulse ring
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .opacity(pulseAnimation ? 0.0 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 2.0)
                                    .repeatForever(autoreverses: false),
                                value: pulseAnimation
                            )
                        
                        // Inner circle background
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.2), Color.red.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .shadow(color: .orange.opacity(0.3), radius: 20, y: 8)
                        
                        // Lock icon
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 50, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Main Content
                    VStack(spacing: 24) {
                        // Title
                        Text("Access Restricted")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        // Subtitle
                        Text("Secure Verification Required")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        // Description
                        VStack(spacing: 16) {
                            Text("This application cannot be opened directly for security reasons.")
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Access must be granted through:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        
                        // Access Methods
                        VStack(spacing: 16) {
                            AccessMethodRow(
                                icon: "link.circle.fill",
                                title: "Secure verification link",
                                description: "From authorized website or email"
                            )
                            
                            AccessMethodRow(
                                icon: "qrcode.viewfinder",
                                title: "QR code scan",
                                description: "From verification service provider"
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Footer
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Protected by advanced security protocols")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Contact your service provider if you need assistance")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 30)
                
                // Hidden Navigation Link
                NavigationLink(
                    destination: photopicker(),
                    isActive: $appState.shouldShowVerification
                ) {
                    EmptyView()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            pulseAnimation = true
        }
    }
}

struct AccessMethodRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            
            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    LockedView()
        .environmentObject(AppState())
}
