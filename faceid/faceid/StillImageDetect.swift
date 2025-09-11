import Foundation
import SwiftUI
import Vision
import CryptoKit
import CoreImage

struct StillImageDetect {

    // MARK: - Requests
    private func createRequests() -> (text: VNRecognizeTextRequest,
                                      faces: VNDetectFaceRectanglesRequest,
                                      landmarks: VNDetectFaceLandmarksRequest,
                                      rects: VNDetectRectanglesRequest,
                                      all: [VNRequest]) {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate

        let faces = VNDetectFaceRectanglesRequest()
        let landmarks = VNDetectFaceLandmarksRequest()
        let rects = VNDetectRectanglesRequest()

        let all: [VNRequest] = [text, faces, landmarks, rects]
        return (text, faces, landmarks, rects, all)
    }

    // MARK: - Geometry helpers
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

        guard let ctx = CGContext(
            data: nil,
            width: Int(rotatedRect.width),
            height: Int(rotatedRect.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        ctx.translateBy(x: rotatedRect.width / 2, y: rotatedRect.height / 2)
        ctx.rotate(by: -angle)
        ctx.translateBy(x: -centerX, y: -centerY)
        ctx.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))

        return ctx.makeImage()
    }

    func averagePoint(from region: VNFaceLandmarkRegion2D) -> CGPoint {
        let pts = region.normalizedPoints
        let c = max(CGFloat(region.pointCount), 1)
        let avgX = pts.map { $0.x }.reduce(0, +) / c
        let avgY = pts.map { $0.y }.reduce(0, +) / c
        return CGPoint(x: avgX, y: avgY)
    }

    // MARK: - Imaging helpers
    func convertToGrayScale(image: UIImage) -> UIImage? {
        guard let ci = CIImage(image: image),
              let f = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        f.setValue(ci, forKey: kCIInputImageKey)
        guard let out = f.outputImage,
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Duplicate single-channel grayscale into 3-channel RGB
    func grayToRGB(image: UIImage) -> UIImage? {
        guard let cgIn = image.cgImage else { return nil }
        let w = cgIn.width, h = cgIn.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cgIn, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }

    func isFlagPresent(in image: CGImage, boundingBox: CGRect) -> CGImage? {
        let W = CGFloat(image.width), H = CGFloat(image.height)
        let pixelRect = CGRect(
            x: boundingBox.origin.x * W,
            y: (1 - boundingBox.origin.y - boundingBox.size.height) * H,
            width: boundingBox.size.width * W,
            height: boundingBox.size.height * H
        ).integral

        guard pixelRect.width > 0, pixelRect.height > 0,
              let cropped = image.cropping(to: pixelRect) else {
            print("Failed to crop image.")
            return nil
        }

        let w = CGFloat(cropped.width), h = CGFloat(cropped.height)
        let cropFlag = CGRect(x: 0, y: 0, width: w * 0.35, height: h * 0.30).integral
        return cropped.cropping(to: cropFlag)
    }

    // MARK: - Hashing & OCR post-process
    func generateHash(stringNames: [String]) -> [String] {
        let nameData = Data(stringNames[0].lowercased().utf8)
        let dobData  = Data(stringNames[1].utf8)

        let hashName = SHA256.hash(data: nameData)
        let hashDOB  = SHA256.hash(data: dobData)

        let hex = { (digest: SHA256.Digest) in digest.map { String(format: "%02hhx", $0) }.joined() }
        let hashString = hex(hashName)
        let hashStringDOB = hex(hashDOB)

        print(hashString)
        print(hashStringDOB)
        return [hashString, hashStringDOB]
    }

    func extractYValues(observations: [VNRecognizedTextObservation]) -> ([String], [String]) {
        var lines: [(text: String, y: CGFloat)] = []

        let blacklist = Set([
            "taranaki","licence","driver","identity","information",
            "raihana","aotearoa","new","zealand","learner","donor","status",
            "restricted","and","govt.nz"
        ])

        for obs in observations {
            guard let cand = obs.topCandidates(1).first else { continue }
            let text = cand.string
            let y = obs.boundingBox.minY
            if !blacklist.contains(text.lowercased()) {
                lines.append((text, y))
            }
        }

        // Group by Y (top-to-bottom)
        lines.sort { $0.y > $1.y }

        var surname: String?
        var firstName: String?
        var birthDate: String?
        var keyNames: [String] = []
        var keyHash: [String] = []

        for (index, line) in lines.enumerated() {
            let lower = line.text.lowercased()

            if lower.contains("surname"),
               index + 1 < lines.count {
                surname = lines[index + 1].text
            }

            if lower.contains("first names"),
               index + 1 < lines.count {
                firstName = lines[index + 1].text
            }

            if lower.contains("date of birth"),
               index + 1 < lines.count {
                // FIX: use the line AFTER, not before
                birthDate = lines[index + 1].text
            }

            if surname != nil, firstName != nil, birthDate != nil {
                let fullName = [firstName, surname].compactMap { $0 }.joined(separator: " ")
                keyNames = [fullName, birthDate!]
                break
            }
        }

        if let s = surname { print("Fallback Surname: \(s)") } else { print("Surname not found via fallback.") }
        if let f = firstName { print("Fallback First Name: \(f)") } else { print("First name not found via fallback.") }
        if let b = birthDate { print("Fallback Birthday: \(b)") } else { print("Birthday not found via fallback.") }

        if !keyNames.isEmpty {
            keyHash = generateHash(stringNames: keyNames)
        }

        return (keyHash, keyNames)
    }

    func parseName2() {
        print("No MRZ detected fallback")
    }

    // MARK: - Main entry
    public func stillImage(
        stillPic: UIImage,
        useGrayscale: Bool = false,
        completion: @escaping (UIImage?, [String]?, [String]?) -> Void
    ) {
        // Normalize orientation to get a stable CGImage
        guard let fixedCG = stillPic.normalizedCGImage() else {
            print("Failed to normalize CGImage")
            completion(nil, nil, nil)
            return
        }

        // Always use .up for a normalized CG image
        let handler = VNImageRequestHandler(cgImage: fixedCG, orientation: .up)

        DispatchQueue.global(qos: .userInitiated).async {
            let reqs = self.createRequests()
            do {
                try handler.perform(reqs.all)

                // --- TEXT ---
                var hashes: [String]? = nil
                var nameDob: [String]? = nil
                if let textObs = reqs.text.results as? [VNRecognizedTextObservation],
                   !textObs.isEmpty {
                    let (h, n) = self.extractYValues(observations: textObs)
                    hashes = h.isEmpty ? nil : h
                    nameDob = n.isEmpty ? nil : n
                }

                // --- FACE LANDMARKS (also implies a face rect exists) ---
                guard let faceObs = reqs.landmarks.results as? [VNFaceObservation],
                      let firstFace = faceObs.first else {
                    print("No face observation found")
                    DispatchQueue.main.async { completion(nil, hashes, nameDob) }
                    return
                }

                // Compute crop rect from normalized bbox
                let W = CGFloat(fixedCG.width)
                let H = CGFloat(fixedCG.height)
                var cropRect = CGRect(
                    x: firstFace.boundingBox.origin.x * W,
                    y: (1 - firstFace.boundingBox.origin.y - firstFace.boundingBox.height) * H,
                    width: firstFace.boundingBox.width * W,
                    height: firstFace.boundingBox.height * H
                ).integral

                cropRect.origin.x = max(0, cropRect.origin.x)
                cropRect.origin.y = max(0, cropRect.origin.y)
                cropRect.size.width  = min(cropRect.size.width,  W - cropRect.origin.x)
                cropRect.size.height = min(cropRect.size.height, H - cropRect.origin.y)

                guard cropRect.width > 0, cropRect.height > 0,
                      let croppedCG = fixedCG.cropping(to: cropRect) else {
                    print("Cropping failed, invalid rect?")
                    DispatchQueue.main.async { completion(nil, hashes, nameDob) }
                    return
                }

                var faceImage = UIImage(cgImage: croppedCG)

                // Optional grayscale pre-processing
                if useGrayscale, let g = self.convertToGrayScale(image: faceImage) {
                    faceImage = g
                }

                // Align face (your FaceAligner is assumed to be async)
                let faceAligner = FaceAligner()
                faceAligner.alignFace(in: faceImage) { alignedFace in
                    var aligned = alignedFace ?? faceImage

                    // Quick post-align landmark sanity check (best effort)
                    if let cg = aligned.cgImage {
                        let checkReq = VNDetectFaceLandmarksRequest()
                        let checkHandler = VNImageRequestHandler(cgImage: cg, orientation: .up)
                        try? checkHandler.perform([checkReq])
                        if let res = checkReq.results as? [VNFaceObservation],
                           let f = res.first,
                           let lms = f.landmarks,
                           let L = lms.leftEye, let R = lms.rightEye {

                            let avg = { (r: VNFaceLandmarkRegion2D) -> CGPoint in
                                let pts = r.normalizedPoints
                                let c = max(CGFloat(r.pointCount), 1)
                                return CGPoint(
                                    x: pts.map { $0.x }.reduce(0, +) / c,
                                    y: pts.map { $0.y }.reduce(0, +) / c
                                )
                            }
                            let l = avg(L), r = avg(R)
                            let lp = CGPoint(x: l.x * aligned.size.width, y: (1 - l.y) * aligned.size.height)
                            let rp = CGPoint(x: r.x * aligned.size.width, y: (1 - r.y) * aligned.size.height)
                            let ang = atan2(rp.y - lp.y, rp.x - lp.x) * 180 / .pi
                            if abs(ang) < 5 {
                                print("✅ Eyes ~horizontal (\(ang)°)")
                            } else {
                                print("❌ Eyes still rotated by \(ang)°")
                            }
                        }
                    }

                    // If the upstream wants RGB 3-channel but we used grayscale, duplicate channels
                    if useGrayscale, let rgb = self.grayToRGB(image: aligned) {
                        aligned = rgb
                    }

                    DispatchQueue.main.async {
                        completion(aligned, hashes, nameDob)
                    }
                }

                // --- Optional: rectangle flag crop (non-blocking / logging only) ---
                if let rectObs = reqs.rects.results as? [VNRectangleObservation],
                   let firstRect = rectObs.first,
                   let _ = self.isFlagPresent(in: fixedCG, boundingBox: firstRect.boundingBox) {
                    print("Successfully cropped ID flag")
                } else {
                    print("No rectangles found or flag crop failed.")
                }

            } catch {
                print("VNRequest failed with error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil, nil, nil) }
            }
        }
    }
}

// MARK: - Orientation normalization
extension UIImage {
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up { return self.cgImage }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized?.cgImage
    }
}
