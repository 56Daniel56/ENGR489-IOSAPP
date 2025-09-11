//
//  FaceAligner.swift
//  faceid
//
//  Created by Daniel Herbert on 28/07/2025.
//

import UIKit
import Vision

class FaceAligner {

    // Public method to align and crop the face
    func alignFace(in image: UIImage, completion: @escaping (UIImage?) -> Void) {
        detectFaceLandmarks(in: image) { face in
            guard let face = face,
                  let aligned = self.rotateImageToAlignEyes(image: image, face: face)
                  //let cropped = self.cropFace(from: aligned, using: face)
            else {
                completion(nil)
                return
            }

            completion(aligned)
        }
    }

    // MARK: - Step 1: Detect landmarks
    private func detectFaceLandmarks(in image: UIImage, completion: @escaping (VNFaceObservation?) -> Void) {
        guard let cgImage = image.cgImage else {
            print("❌ Failed to get CGImage from UIImage")
            completion(nil)
            return
        }
        
        // Debug: Print image properties to confirm processing different images
        let timestamp = Date().timeIntervalSince1970
        print("=== detectFaceLandmarks at \(timestamp) ===")
        print("Processing image - Size: \(image.size), Scale: \(image.scale)")
        print("CGImage size: \(cgImage.width)x\(cgImage.height)")
        print("Image memory address: \(Unmanaged.passUnretained(image).toOpaque())")
        
        // Create a fresh request each time (don't reuse)
        let request = VNDetectFaceLandmarksRequest { request, error in
            if let error = error {
                print("❌ VNDetectFaceLandmarksRequest error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let results = request.results as? [VNFaceObservation] else {
                print("❌ Failed to cast results to [VNFaceObservation]")
                completion(nil)
                return
            }
            
            guard let first = results.first else {
                print("❌ No face observations found in results")
                completion(nil)
                return
            }
            
            // Debug: Print face detection results
            print("✅ Found \(results.count) face(s)")
            print("Face bounding box: \(first.boundingBox)")
            
            // Debug: Print landmark availability
            if let landmarks = first.landmarks {
                print("Landmarks available - Left eye: \(landmarks.leftEye != nil), Right eye: \(landmarks.rightEye != nil)")
            } else {
                print("⚠️ No landmarks detected")
            }
            
            completion(first)
        }
        
        // Configure request
        request.usesCPUOnly = false // Let it use GPU if available for consistency
        
        // Create fresh handler each time
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("❌ Failed to perform VNDetectFaceLandmarksRequest: \(error.localizedDescription)")
            completion(nil)
        }
    }

    // MARK: - Step 2: Rotate to align eyes
    private func rotateImageToAlignEyes(image: UIImage, face: VNFaceObservation) -> UIImage? {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else { return nil }

        func averagePoint(from region: VNFaceLandmarkRegion2D) -> CGPoint {
            let points = region.normalizedPoints
            let count = CGFloat(region.pointCount)
            let avgX = points.map { $0.x }.reduce(0, +) / count
            let avgY = points.map { $0.y }.reduce(0, +) / count
            return CGPoint(x: avgX, y: avgY)
        }

        let left = averagePoint(from: leftEye)
        let right = averagePoint(from: rightEye)
        
        

        let imageSize = image.size
        let leftPt = CGPoint(x: left.x * imageSize.width, y: (1 - left.y) * imageSize.height)
        let rightPt = CGPoint(x: right.x * imageSize.width, y: (1 - right.y) * imageSize.height)

        let deltaX = rightPt.x - leftPt.x
        let deltaY = rightPt.y - leftPt.y
        let angle = atan2(deltaY, deltaX)
      
        
        print("Left eye point: \(leftPt)")
        print("Right eye point: \(rightPt)")
        print("Angle: \(angle * 180 / .pi) degrees")

        return rotate(image: image, by: -angle)
    }

    private func rotate(image: UIImage, by radians: CGFloat) -> UIImage? {
        let newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)

        image.draw(in: CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        ))

        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage
    }

}
