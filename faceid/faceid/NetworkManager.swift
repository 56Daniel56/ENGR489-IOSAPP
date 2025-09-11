//
//  NetworkManager.swift
//  faceid
//
//  Created by Daniel Herbert on 22/07/2025.
//

import Foundation
import DeviceCheck
import CryptoKit
import UIKit

class NetworkManager {
    static let shared = NetworkManager()
    
    private let keyStorageKey = "AppAttestKeyID"
    private let address = "192.168.8.136"
    private let firstLaunchKey = "HasLaunchedBefore"
    var message: String = ""
    var id: String = ""
    var fullName: String = ""
    var birth: String = ""
    let idfv = UIDevice.current.identifierForVendor?.uuidString
    
    func prepareappatest(message: String, id: String, fulName: String, birth: String) {
        self.message = message
        self.id = id
        self.fullName = fulName
        self.birth = birth

        guard DCAppAttestService.shared.isSupported else {
            print("❌ App Attest not supported")
            return
        }
        
        if let existingKeyID = UserDefaults.standard.string(forKey: keyStorageKey) {
            print("✅ Using existing App Attest key: \(existingKeyID)")
            print("🔍 Existing key length: \(existingKeyID.count) characters")
            signWithAppatest(keyID: existingKeyID)
        } else {
            print("🔑 No existing key found, generating new App Attest key...")
            DCAppAttestService.shared.generateKey { keyID, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Failed to generate key:", error)
                        return
                    }
                    
                    guard let keyID = keyID else {
                        print("❌ Key generation returned nil")
                        return
                    }
                    
                    print("✅ Generated new App Attest key ID: \(keyID)")
                    print("🔍 New key length: \(keyID.count) characters")
                    print("🔍 Key ID first 20 chars: \(String(keyID.prefix(20)))...")
                    
                    UserDefaults.standard.set(keyID, forKey: self.keyStorageKey)
                    
                    self.signWithAppatest(keyID: keyID)
                }
            }
        }
    }
    
    func signWithAppatest(keyID: String) {
        if let appID = Bundle.main.bundleIdentifier {
            print("App ID (Bundle Identifier): \(appID)")
        }
        
        let baseURL = "http://\(address):5050/appatest"
        var components = URLComponents(string: baseURL)!
        
        // Properly encode the keyID to handle special characters like +
        let encodedKeyID = keyID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyID
        print("🔗 Original keyID: \(keyID)")
        print("🔗 Encoded keyID: \(encodedKeyID)")
        
        components.queryItems = [
            URLQueryItem(name: "keyID", value: keyID)  // URLQueryItem handles encoding automatically
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let challengeString = json["challenge"] as? String {
                    
                    print("Base64 Challenge from server: \(challengeString)")
                    
                    // Convert Base64 challenge to Data
                    if let challengeData = Data(base64Encoded: challengeString) {
                        let hash = Data(SHA256.hash(data: challengeData))
                        print("SHA256 hash of challenge: \(hash.base64EncodedString())")
                        
                        self.atestkey(keyID: keyID, clientDataHash: hash, challenge: challengeString)
                    } else {
                        print("Failed to decode base64 challenge")
                    }
                } else {
                    print("Invalid JSON structure")
                }
            } catch {
                print("Failed to parse JSON: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    func atestkey(keyID: String, clientDataHash: Data, challenge: String) {
        let hash = clientDataHash
        print("🔐 Attesting keyID: \(keyID)")
        print("📊 clientDataHash (base64): \(hash.base64EncodedString())")
        print("✅ Is AppAttest supported? \(DCAppAttestService.shared.isSupported)")
        
        DCAppAttestService.shared.attestKey(keyID, clientDataHash: hash) { attestation, error in
            if let error = error {
                print("❌ Key attest failed: \(error.localizedDescription)")
                if let error = error as NSError? {
                    print("❌ Error details - code: \(error.code), domain: \(error.domain)")
                    
                    // Handle the invalid key error specifically
                    if error.code == 2 {
                        print("❌ App Attest key is invalid (probably wiped on reinstall). Regenerating.")
                        UserDefaults.standard.removeObject(forKey: self.keyStorageKey)
                        self.generateNewKey()
                    }

                }
                return
            }
            
            guard let attestation = attestation else {
                print("❌ Attestation data is nil")
                return
            }
            
            let attestationString = attestation.base64EncodedString()
            print("✅ Attestation successful!")
            print("📄 Attestation length: \(attestationString.count) characters")
            
            // Send the attestation object to your server for verification
            var request = URLRequest(url: URL(string: "http://\(self.address):5050/appatest")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "keyID": keyID,
                "attestation": attestationString
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Failed to send attestation: \(error)")
                    return
                }
                
                print("✅ Attestation successfully sent and verified.")
                self.appatestService(keyID: keyID, challenge: challenge)
            }
            
            task.resume()
        }
    }
    
    func generateNewKey() {
        DCAppAttestService.shared.generateKey { keyID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Key generation failed: \(error)")
                    return
                }

                guard let keyID = keyID else {
                    print("❌ Key generation returned nil")
                    return
                }

                UserDefaults.standard.set(keyID, forKey: self.keyStorageKey)
                print("✅ New key generated and stored")
                self.signWithAppatest(keyID: keyID)
            }
        }
    }
    
    func appatestService(keyID: String, challenge: String) {
        guard let url = URL(string: "http://\(address):5050/verify") else { return }
      
        
        let payload = ["message": message, "ID": id, "name": fullName, "dob": birth, "challenge": challenge, "userID": "daniel", "deviceID": idfv]
        guard let clientData = try? JSONEncoder().encode(payload) else { return }
        let clientDataHash = Data(SHA256.hash(data: clientData))
        
      
        
        DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, error in
            guard error == nil else {
                print("error encountered generating assertion")
                return
            }
            
            // Send the assertion and request to your server
            
            let requestBody: [String: Any] = [
                
                "clientData": payload,
                "assertion": assertion?.base64EncodedString()
            ]
            guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else{
                print("failed to serialize request body")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = httpBody
            
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error:", error.localizedDescription)
                } else if let httpResponse = response as? HTTPURLResponse{
                    print("Request sent successfully!:", httpResponse.statusCode)
                }
            }.resume()
        }
    }
}
