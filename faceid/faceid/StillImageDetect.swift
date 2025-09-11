import Foundation
import SwiftUI
import Vision
import CryptoKit
struct StillImageDetect {
    
    // Remove the options property and create requests directly
    // var options = GenerateOptions()  // DELETE THIS LINE
    
    // Add this method to create fresh requests each time
    private func createRequests() -> [VNRequest] {
        var listofrequest: [VNRequest] = []
        
        let requestReturns = VNRecognizeTextRequest()
        requestReturns.recognitionLevel = .accurate
        //requestReturns.usesCPUOnly = true
        listofrequest.append(requestReturns)
        
        let face = VNDetectFaceRectanglesRequest()
        //face.usesCPUOnly = true
        listofrequest.append(face)
        
        let features = VNDetectFaceLandmarksRequest()
        //features.usesCPUOnly = true
        listofrequest.append(features)
        
        let rectangle = VNDetectRectanglesRequest()
        //rectangle.usesCPUOnly = true
        listofrequest.append(rectangle)
        
        return listofrequest
    }
    
    // ... all your existing methods (rotate, averagePoint, etc.) stay the same ...
    
    func rotate(image: CGImage, leftEye: CGPoint, rightEye: CGPoint) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let centerX = (leftEye.x + rightEye.x) / 2
        let centerY = (leftEye.y + rightEye.y) / 2
        let deltaX = rightEye.x - leftEye.x
        let deltaY = rightEye.y - leftEye.y
        let angle = atan2(deltaY, deltaX)

        let rotatedRect = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            .applying(CGAffineTransform(rotationAngle: -angle))
            .integral

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: Int(rotatedRect.width),
            height: Int(rotatedRect.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            return nil
        }

        // Move origin to center between eyes
        context.translateBy(x: rotatedRect.width / 2, y: rotatedRect.height / 2)
        context.rotate(by: -angle)

        // Now draw image so that the rotation center (eye midpoint) is centered
        context.translateBy(x: -centerX, y: -centerY)
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))

        return context.makeImage()
    }

    func averagePoint(from region: VNFaceLandmarkRegion2D) -> CGPoint {
        let points = region.normalizedPoints
        let count = CGFloat(region.pointCount)
        let avgX = points.map { $0.x }.reduce(0, +) / count
        let avgY = points.map { $0.y }.reduce(0, +) / count
        return CGPoint(x: avgX, y: avgY)
    }
    
    func convertToGrayScale(image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let grayscale = CIFilter(name: "CIPhotoEffectMono")
        grayscale?.setValue(ciImage, forKey: kCIInputImageKey)

        if let outputCIImage = grayscale?.outputImage,
           let cgImage = CIContext().createCGImage(outputCIImage, from: outputCIImage.extent) {
            return UIImage(cgImage: cgImage)
        }

        return nil
    }
    
    func isFlagPresent(in image: CGImage, boundingBox: CGRect) -> CGImage? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let pixelRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.size.height) * imageHeight,
            width: boundingBox.size.width * imageWidth,
            height: boundingBox.size.height * imageHeight
        )
        guard let cropped = image.cropping(to: pixelRect) else {
            print("Failed to crop image.")
            return nil
        }

        let croppedWidth = CGFloat(cropped.width)
        let croppedHeight = CGFloat(cropped.height)
        let widthRatio = 0.35
        let heightRatio = 0.30
        
        let cropFlag = CGRect(
            x: 0,
            y: 0,
            width: croppedWidth * widthRatio,
            height: croppedHeight * heightRatio
        )
        
        let flag = cropped.cropping(to: cropFlag)
        return flag
    }
    
    func generateHash(stringNames: [String]) -> [String] {
        let nameData = Data(stringNames[0].lowercased().utf8)
        let dobData = Data(stringNames[1].utf8)
        
        
        print(Array(nameData))  // Prints the bytes as [UInt8]
        print(Array(dobData))
        
        let hashName = SHA256.hash(data: nameData)
        let hashDOB = SHA256.hash(data: dobData)
            
            // Convert hash to a hex string
        let hashString = hashName.map { String(format: "%02hhx", $0) }.joined()
        let hashStringDOB = hashDOB.map{String(format: "%02hhx", $0)}.joined()
        print(hashString)
        print(hashStringDOB)
            
        return [hashString, hashStringDOB]
    }
    
    func extractYValues(observations: [VNRecognizedTextObservation]) -> ([String], [String]) {
        var lines: [(text: String, y: CGFloat)] = []
        
        let blacklist = [
            "taranaki", "licence", "driver", "identity", "information",
            "raihana", "aotearoa", "new", "zealand", "learner", "donor", "status",
            "restricted", "and", "govt.nz"
        ]
        
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let y = observation.boundingBox.minY
            if !blacklist.contains(text.lowercased()) {
                lines.append((text, y))
            }
        }
        
        lines.sort { $0.y > $1.y }
        var newLines: [String] = []
        var currentLine: [String] = []
        var lastY: CGFloat?
        
        for (text, y) in lines {
            if let last = lastY, abs(y - last) > 0.01 {
                if !currentLine.isEmpty {
                    newLines.append(currentLine.joined(separator: " "))
                    currentLine = []
                }
            }
            currentLine.append(text)
            lastY = y
        }
        
        if !currentLine.isEmpty {
            newLines.append(currentLine.joined(separator: " "))
        }

    
        
        var surname: String?
        var firstName: String?
        var birthDate: String?
        var keyNames: [String] = []
        var keyHash: [String] = []
        
        for (index, line) in lines.enumerated() {
            let lower = line.text.lowercased()
            
            if lower.contains("surname") {
                if index + 1 < lines.count {
                    surname = lines[index + 1].text
                }
            }

            if lower.contains("first names") {
                if index + 1 < lines.count {
                    firstName = lines[index + 1].text
                }
            }
            
            if lower.contains("date of birth") {
                if index + 1 < lines.count {
                    birthDate = lines[index - 1].text
                }
            }

            if surname != nil && firstName != nil && birthDate != nil {
                let fullName = [firstName, surname].compactMap { $0 }.joined(separator: " ")
                keyNames.append(fullName)
                keyNames.append(birthDate!)
                break
            }
        }
        
        if let s = surname {
            print("Fallback Surname: \(s)")
        } else {
            print("Surname not found via fallback.")
        }

        if let f = firstName {
            print("Fallback First Name: \(f)")
        } else {
            print("First name not found via fallback.")
        }
        
        if let b = birthDate {
            print("Fallback Birthday: \(b)")
        } else {
            print("Birthday not found via fallback.")
        }
        if(!keyNames.isEmpty){
            keyHash = generateHash(stringNames: keyNames)
        }
        
        return (keyHash, keyNames)
    }

    func parseName2() {
        print("No MRZ detected fallback")
    }
    
    public func stillImage(stillPic: UIImage, completion: @escaping (UIImage?, [String]?, [String]?) -> Void) {
        let imageOrientation: CGImagePropertyOrientation = {
            switch stillPic.imageOrientation {
            case .up: return .up
            case .upMirrored: return .upMirrored
            case .down: return .down
            case .downMirrored: return .downMirrored
            case .left: return .left
            case .leftMirrored: return .leftMirrored
            case .right: return .right
            case .rightMirrored: return .rightMirrored
            @unknown default:
                return .up
            }
        }()
        
        let fixedCG = stillPic.normalizedCGImage()
        
        let imageRequestHandler = VNImageRequestHandler(cgImage: fixedCG!, orientation: .up)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create fresh requests for each call - THIS IS THE KEY FIX
                let requests = self.createRequests()
                try imageRequestHandler.perform(requests)
                
                print("Array length: \(requests.count)")
                
                let observation = requests[0].results as? [VNRecognizedTextObservation]
                
                let strings = observation?.compactMap { observation in
                    return observation.topCandidates(1).first?.string
                }
                //var stringlist = strings
                let (stringlist, stringlist2) = self.extractYValues(observations: observation!)
                
                let landmarks = requests[2].results as? [VNFaceObservation]
                
              
                guard let faceobs = landmarks?.first else {
                    print("No face observation found")
                    completion(nil, nil, nil)
                    return
                }
                
                let width = fixedCG!.width
                let height = fixedCG!.height
                
                let bbox = faceobs.boundingBox

                var cropX = bbox.origin.x * CGFloat(width)
                var cropY = (1 - bbox.origin.y - bbox.height) * CGFloat(height)
                var cropW = bbox.width * CGFloat(width)
                var cropH = bbox.height * CGFloat(height)

                cropX = max(0, cropX)
                cropY = max(0, cropY)
                if cropX + cropW > CGFloat(width) {
                    cropW = CGFloat(width) - cropX
                }
                if cropY + cropH > CGFloat(height) {
                    cropH = CGFloat(height) - cropY
                }

                let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
                print("Crop rect:", cropRect)
                
                guard let croppedCGImage = fixedCG?.cropping(to: cropRect) else {
                    print("Cropping failed, invalid rect?")
                    return
                }
                
                let croppedImage = UIImage(cgImage: croppedCGImage)
                let greyScale = self.convertToGrayScale(image: croppedImage)
                
                // In your StillImageDetect, replace the FaceAligner section with this:

                print("=== BEFORE FACE ALIGNER ===")

                let faceAligner = FaceAligner()
                faceAligner.alignFace(in: greyScale!) { alignedFace in
                    if let aligned = alignedFace {
                        print("=== AFTER FACE ALIGNER ===")
                        print("Aligned image size: \(aligned.size)")
                        
                        // Test: Detect landmarks again to see if eyes are now horizontal
                        let testRequest = VNDetectFaceLandmarksRequest { request, error in
                            if let results = request.results as? [VNFaceObservation],
                               let face = results.first,
                               let landmarks = face.landmarks,
                               let leftEye = landmarks.leftEye,
                               let rightEye = landmarks.rightEye {
                                
                                let averagePoint = { (region: VNFaceLandmarkRegion2D) -> CGPoint in
                                    let points = region.normalizedPoints
                                    let count = CGFloat(region.pointCount)
                                    let avgX = points.map { $0.x }.reduce(0, +) / count
                                    let avgY = points.map { $0.y }.reduce(0, +) / count
                                    return CGPoint(x: avgX, y: avgY)
                                }
                                
                                let left = averagePoint(leftEye)
                                let right = averagePoint(rightEye)
                                
                                let leftPt = CGPoint(x: left.x * aligned.size.width, y: (1 - left.y) * aligned.size.height)
                                let rightPt = CGPoint(x: right.x * aligned.size.width, y: (1 - right.y) * aligned.size.height)
                                
                                let newDeltaX = rightPt.x - leftPt.x
                                let newDeltaY = rightPt.y - leftPt.y
                                let newAngle = atan2(newDeltaY, newDeltaX)
                                
                                print("POST-ROTATION: Left eye: \(leftPt), Right eye: \(rightPt)")
                                print("POST-ROTATION: New angle: \(newAngle * 180 / .pi) degrees")
                                
                                if abs(newAngle * 180 / .pi) < 5 {
                                    print("✅ SUCCESS: Eyes are now nearly horizontal!")
                                } else {
                                    print("❌ PROBLEM: Eyes are still rotated by \(newAngle * 180 / .pi) degrees")
                                }
                            }
                        }
                        
                        guard let cgImage = aligned.cgImage else { return }
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try? handler.perform([testRequest])
                        
                        DispatchQueue.main.async {
                            completion(greyScale, stringlist, stringlist2)  // Return the aligned image
                        }
                    } else {
                        print("❌ FaceAligner returned nil")
                        DispatchQueue.main.async {
                            completion(greyScale, stringlist, stringlist2)  // Fallback to unrotated
                        }
                    }
                }
                
                if let idRectangles = requests[3].results as? [VNRectangleObservation],
                   let firstRect = idRectangles.first {
                    
                    
                    if let croppedID = self.isFlagPresent(in: fixedCG!, boundingBox: firstRect.boundingBox) {
                        let croppedImage = UIImage(cgImage: croppedID)
                        print("Successfully cropped ID flag")
                    } else {
                        print("Flag not present or cropping failed.")
                    }
                } else {
                    print("No rectangles found or cast failed.")
                }
                
            } catch {
                print("failed VNrequest")
                print("VNRequest failed with error: \(error.localizedDescription)")
                return
            }
        }
    }
}

extension UIImage {
    func normalizedCGImage() -> CGImage? {
        // If already in .up orientation, no need to redraw
        if imageOrientation == .up {
            return self.cgImage
        }

        // Create a new image context (same size & scale)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)

        // Draw the image into the context (this applies the orientation transform)
        draw(in: CGRect(origin: .zero, size: size))

        // Grab the "flattened" image from the context
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()

        // Clean up
        UIGraphicsEndImageContext()

        // Return the CGImage from the normalized UIImage
        return normalizedImage?.cgImage
    }
}
