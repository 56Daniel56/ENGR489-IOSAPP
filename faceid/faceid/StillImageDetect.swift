//
//  StillImageDetect.swift
//  faceid
//
//  Created by Daniel Herbert on 20/05/2025.
//

import Foundation
import SwiftUI
import Vision

class GenerateOptions{
    
    //lazy var request: VNDetectFaceRectanglesRequest = {
        //let requestReturns = VNDetectFaceRectanglesRequest()
    
    lazy var request: [VNRequest] = {
        var listofrequest: [VNRequest] = []
        let requestReturns = VNRecognizeTextRequest()
        
        //this line is for simulator only
       requestReturns.usesCPUOnly = true
        listofrequest.append(requestReturns)
        
        let face = VNDetectFaceRectanglesRequest()
        face.usesCPUOnly = true
        listofrequest.append(face)
        
        let features = VNDetectFaceLandmarksRequest()
        features.usesCPUOnly = true
        listofrequest.append(features)
        
        return listofrequest
        
    }()
    
}

struct StillImageDetect{
    
    
    var options = GenerateOptions()
    
    public func stillImage(stillPic:UIImage){
        let imageOrientation: CGImagePropertyOrientation = {
            switch stillPic.imageOrientation{
            case .up: return.up
            case .upMirrored: return.upMirrored
            case .down: return.down
            case .downMirrored: return.downMirrored
            case .left: return.left
            case .leftMirrored: return.leftMirrored
            case .right: return.right
            case .rightMirrored: return.rightMirrored
            @unknown default:
                return.up
            }
            
        }()
        
        
        
        let imageRequestHandler = VNImageRequestHandler(cgImage: stillPic.cgImage!, orientation: imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            do{
                try imageRequestHandler.perform(options.request)
                
                //print("these are the text ones")
                
                print("Array length: \(options.request.count)")
                
                let observation = options.request[0].results as? [VNRecognizedTextObservation]
                let strings = observation?.compactMap{ observation in
                    // Return the string of the top VNRecognizedText instance.
                    return observation.topCandidates(1).first?.string
                }
                //print(strings)
                       
       
               // print("these are the face ones")
                print(options.request[2])
                let landmarks = options.request[2].results as? [VNFaceObservation]
                //print(landmarks)
                if let landmarks = landmarks{
                    for landmark in landmarks{
                        
                        print(landmark.landmarks?.innerLips)
                    }
                }

                
                //print(options.request[2].results)
    
            }catch{
                print("failed VNrequest")
                print("VNRequest failed with error: \(error.localizedDescription)")
                return
            }
        }
        
    }
    
    
}


