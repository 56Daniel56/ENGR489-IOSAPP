//
//  faceidApp.swift
//  faceid
//
//  Created by Daniel Herbert on 19/05/2025.
//

import SwiftUI
//import FirebaseCore


//class AppDelegate: UIResponder, UIApplicationDelegate {

    //func application(_ application: UIApplication,
    //               didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        //FirebaseApp.configure()
      //  return true
    //}
   
 //}
import DeviceCheck


@main
struct faceidApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var callback2: String? = nil
    
    
    init() {
        let service = DCAppAttestService.shared
        if service.isSupported {
            print("✅ App Attest is supported!!")
            // Perform key generation and attestation here
        } else {
            print("❌ App Attest is NOT supported.")
        }
        
        // Continue with any other server or setup logic
    }
    
    
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isUnlocked {
                    photopicker()
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            print("applicationDidBecomeActive")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            print("applicationWillEnterForeground")
                            handleAppDidBecomeActive()
                        }
                } else {
                    LockedView()
                }
            }
            .onOpenURL { url in
                if url.scheme == "myapp" {
                    handleIncomingURL(url)
                    appState.isUnlocked = true
                }
            }
            .environmentObject(appState)

        }
    }
    
    
    func handleAppDidBecomeActive() {
        print("App became active - from function")
        // Your logic here
    }
    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "myapp", url.host == "verify" else {
            print("Invalid scheme or host")
            return
        }
        
        appState.shouldShowVerification = true

        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        let queryItems = components?.queryItems
        
        let sessionId = queryItems?.first(where: { $0.name == "sessionId" })?.value
        let callback = queryItems?.first(where: { $0.name == "callback" })?.value
        print("Session ID:", sessionId ?? "nil")
        print("Callback:", callback ?? "nil")
        
        // Now pass to SwiftUI view, for verification flow
        if let sessionId = sessionId, let callback = callback {
            appState.callback = callback
            appState.sessionId = sessionId
        }
    }
}
