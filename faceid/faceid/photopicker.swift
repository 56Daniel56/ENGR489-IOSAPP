//
//  photopicker.swift
//  faceid
//
//  Created by Daniel Herbert on 19/05/2025.
//
//test
import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import CoreML

final class PhotoPickerViewModel: ObservableObject{
    @Published var selectedImage: UIImage? = nil
    @Published var secondImage: UIImage? = nil
    
    @Published var seccondSelected: PhotosPickerItem? = nil{
        didSet {
            setImage(from: seccondSelected, number:2)
        }
    }
    
    @Published var imageSelected: PhotosPickerItem? = nil{
        didSet {
            setImage(from: imageSelected, number:1)
        }
    }
    
    private func setImage(from selection : PhotosPickerItem?, number:Int){
        guard let selection else { return }
        Task {
            do {
                if let data = try await selection.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        if number == 2 {
                            self.secondImage = uiImage
                        } else {
                            self.selectedImage = uiImage
                        }
                    }
                }
            } catch {
                print("Photo load failed: \(error)")
            }
        }
    }
}

struct photopicker: View {
    @State private var isShowingCamera1 = false
    @State private var isShowingCamera2 = false
    @StateObject private var viewModel = PhotoPickerViewModel()
    @StateObject private var viewModel2 = PhotoPickerViewModel()
    @State private var cropped1: UIImage? = nil
    @State private var cropped2: UIImage? = nil
    let detector = StillImageDetect()
    @State private var extractedName: String? = nil
    @State private var extractedDOB: String? = nil

    @State private var navigate = false
    @State private var match = ""
    @State private var idStrings: [String] = []
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    
    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            print(granted ? "✅ Camera access granted." : "❌ Camera access denied.")
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header Section
                        VStack(spacing: 8) {
                            Image(systemName: "faceid")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("Face ID Verification")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Secure identity comparison using advanced biometric analysis")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)
                        
                        // Image Comparison Section
                        VStack(spacing: 24) {
                            HStack(spacing: 20) {
                                ImageCard(
                                    title: "ID Document",
                                    image: viewModel.selectedImage,
                                    croppedImage: cropped1,
                                    systemIcon: "doc.text.viewfinder",
                                    isEmpty: viewModel.selectedImage == nil
                                )
                                
                                VStack {
                                    Text("VS")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                        .padding(12)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                
                                ImageCard(
                                    title: "Live Photo",
                                    image: viewModel2.secondImage,
                                    croppedImage: cropped2,
                                    systemIcon: "person.crop.square",
                                    isEmpty: viewModel2.secondImage == nil
                                )
                            }
                            .padding(.horizontal)
                        }
                        
                        // Action Buttons Section
                        VStack(spacing: 16) {
                            VStack(spacing: 12) {
                                Text("ID Document")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $viewModel.imageSelected) {
                                        ActionButton(
                                            title: "Photo Library",
                                            icon: "photo.on.rectangle",
                                            color: .blue
                                        )
                                    }
                                    
                                    Button { isShowingCamera1 = true } label: {
                                        ActionButton(
                                            title: "Camera",
                                            icon: "camera",
                                            color: .blue
                                        )
                                    }
                                }
                            }
                            
                            Divider().padding(.horizontal, 40)
                            
                            VStack(spacing: 12) {
                                Text("Live Photo")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $viewModel2.seccondSelected) {
                                        ActionButton(
                                            title: "Photo Library",
                                            icon: "photo.on.rectangle",
                                            color: .green
                                        )
                                    }
                                    
                                    Button { isShowingCamera2 = true } label: {
                                        ActionButton(
                                            title: "Camera",
                                            icon: "camera",
                                            color: .green
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Compare Button
                        Button {
                            compareImages()
                        } label: {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                        .font(.title3)
                                }
                                
                                Text(isProcessing ? "Analyzing..." : "Compare Faces")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: canCompare ? [Color.blue, Color.blue.opacity(0.8)] : [Color.gray, Color.gray.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: canCompare ? .blue.opacity(0.3) : .clear, radius: 8, y: 4)
                        }
                        .disabled(!canCompare || isProcessing)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                        
                        // Spacer for nav
                        Spacer(minLength: 24)
                    }
                }
                
                // Navigation Link (Hidden)
                NavigationLink(
                    destination: resultsview(match: String(match), message: idStrings, name: extractedName, dob: extractedDOB),
                    isActive: $navigate
                ) { EmptyView() }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $isShowingCamera1) {
                CameraView(image: $viewModel.selectedImage)
            }
            .sheet(isPresented: $isShowingCamera2) {
                CameraView(image: $viewModel2.secondImage)
            }
            .onAppear { requestCameraAccess() }
        }
    }
    
    private var canCompare: Bool {
        viewModel.selectedImage != nil && viewModel2.secondImage != nil
    }
    
    private func compareImages() {
        errorMessage = nil
        guard let img1 = viewModel.selectedImage, let img2 = viewModel2.secondImage else { return }
        isProcessing = true
        
        // Step 1: detect and crop on a background task
        Task.detached {
            // Crop/align first image
            let group = DispatchGroup()
            var crop1: UIImage?
            var crop2: UIImage?
            var labels: [String]?
            var nameDOB: [String]?
            
            group.enter()
            detector.stillImage(stillPic: img1) { faceImage1, idLabels, capturedValues in
                crop1 = faceImage1
                labels = idLabels
                nameDOB = capturedValues
                group.leave()
            }
            
            group.enter()
            let detector2 = StillImageDetect()
            detector2.stillImage(stillPic: img2) { faceImage2, _, _ in
                crop2 = faceImage2
                group.leave()
            }
            
            group.wait()
            
            guard let c1 = crop1, let c2 = crop2 else {
                await MainActor.run {
                    self.errorMessage = "Couldn’t detect a face in one or both images."
                    self.isProcessing = false
                }
                return
            }
            
            await MainActor.run {
                self.cropped1 = c1
                self.cropped2 = c2
                if let labels = labels, !labels.isEmpty {
                    self.idStrings = labels
                }

                if let nameDOB = nameDOB, nameDOB.count >= 2 {
                    self.extractedName = nameDOB[0]   // full name
                    self.extractedDOB  = nameDOB[1]   // date of birth
                } else {
                    self.extractedName = nil
                    self.extractedDOB  = nil
                }
            }
            
            // Step 2: run embeddings off the main thread
            do {
                let model = try interfacecoreml()
                let embA = try model.runModelPrediction(picture: c1)
                let embB = try model.runModelPrediction(picture: c2)
                
                guard let arrA = embA.toFloatArray(),
                      let arrB = embB.toFloatArray(),
                      arrA.count == arrB.count else {
                    await MainActor.run {
                        self.errorMessage = "Embedding conversion failed."
                        self.isProcessing = false
                    }
                    return
                }
                
                let sim = cosineSimilarity(arrA, arrB) // in [-1, 1]
                
                // Set a sensible threshold; tune with your data.
                // For ArcFace-like exports, 0.5–0.6 is common for same-person after proper alignment.
                
                let threshold: Float = 0.50
                print("threshold: ",sim)
                let isMatch = sim >= threshold
                
                await MainActor.run {
                    self.match = isMatch ? "Faces match" : "Faces do not match"
                    self.isProcessing = false
                    self.navigate = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Model prediction failed: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
}

// MARK: - Helpers

private func l2Normalize(_ vec: [Float]) -> [Float] {
    let denom = sqrt(vec.reduce(0) { $0 + $1 * $1 })
    if denom < 1e-12 { return vec.map { _ in 0 } }
    return vec.map { $0 / denom }
}

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    let na = l2Normalize(a)
    let nb = l2Normalize(b)
    var acc: Float = 0
    for i in 0..<min(na.count, nb.count) { acc += na[i] * nb[i] }
    return acc
}

private extension MLMultiArray {
    func toFloatArray() -> [Float]? {
        guard dataType == .float32 else { return nil }
        let count = self.count
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { dst in
            let src = self.dataPointer.bindMemory(to: Float.self, capacity: count)
            dst.baseAddress?.assign(from: src, count: count)
        }
        return result
    }
}

// MARK: - Supporting Views (unchanged)

struct ImageCard: View {
    let title: String
    let image: UIImage?
    let croppedImage: UIImage?
    let systemIcon: String
    let isEmpty: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(width: 140, height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: systemIcon)
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No Image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let croppedImage = croppedImage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(uiImage: croppedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 4)
                                .padding(8)
                        }
                    }
                }
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
