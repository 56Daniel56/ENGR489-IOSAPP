//
//  interfacecoreml.swift
//  faceid
//
//  Created by Daniel Herbert on 13/07/2025.
//

import CoreML
import Vision
import UIKit
import Foundation


class interfacecoreml{
    func runModelPrediction(picture: UIImage) -> MLMultiArray{
        // Your prediction code here
        
        func imageToMLMultiArray(_ image: UIImage) -> MLMultiArray {
            // Resize UIImage to 112x112
            let resizedImage = image.resizeToExact(targetSize: CGSize(width: 112, height: 112))
            
            // Convert UIImage to CGImage
            let cgImage = resizedImage!.cgImage
            
            // Create MLMultiArray
            let shape = [1, 1, 3, 112, 112] as [NSNumber]
            let mlArray = try! MLMultiArray(shape: shape, dataType: .float32)
            
            // Create a context to extract pixel data
            let width = 112
            let height = 112
            let bytesPerRow = width * 4
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)
            defer { rawData.deallocate() }
            
            let context = CGContext(data: rawData, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            
            
            context!.draw(cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Fill MLMultiArray in channel-first order: [sequence, batch, channel, height, width]
            // Here sequence=0, batch=0 fixed since 1 and 1
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let r = Float(rawData[pixelIndex])     // Red
                    let g = Float(rawData[pixelIndex + 1]) // Green
                    let b = Float(rawData[pixelIndex + 2]) // Blue
                    
                    
                    
                    
                    let bNorm = (b) / 255.0
                    let gNorm = (g) / 255.0
                    let rNorm = (r) / 255.0
                    
                    
                    // Assign to MLMultiArray
                    mlArray[[0, 0, 0, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: bNorm)
                    mlArray[[0, 0, 1, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: gNorm)
                    mlArray[[0, 0, 2, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: rNorm)
                    
                }
            }
            
            return mlArray
        }


        guard let resizedImage = picture.resizeToExact(targetSize: CGSize(width: 112, height: 112)),
              let pixelBuffer = pixelBuffer(from: resizedImage, size: CGSize(width: 112, height: 112)) else {
            fatalError("Could not resize or convert image to pixel buffer")
        }
        
        
        print("Running model prediction")
        
        guard let model = try? _360model(configuration: MLModelConfiguration()) else {
            fatalError("Failed to load model")
        }
        
        print("Model is running")
        // Load model, prepare image, run prediction...
        let multiarray = imageToMLMultiArray(picture)
        let input = _360modelInput(input_1: multiarray)
        let output = try? model.prediction(input: input)
        let outputValue = output!.featureValue(for: "1333")
        let embeddingA = outputValue?.multiArrayValue
        
        print(output!.featureNames)
        
        return embeddingA!
        
            
            
        }
     
        
        
        
    }
    
        
        
    
    
    func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        // Create attributes for the pixel buffer
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         attributes as CFDictionary,
                                         &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }

        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else {
            return nil
        }

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()

        return buffer
    }

    // Call the function
    
    // Load the model

extension UIImage {
    func resizeToExact(targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage
    }
}
