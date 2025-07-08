//
//  photopicker.swift
//  faceid
//
//  Created by Daniel Herbert on 19/05/2025.
//

import SwiftUI
import PhotosUI

final class PhotoPickerViewModel: ObservableObject{
    
    @Published private(set) var selectedImage: UIImage? = nil
    @Published private(set) var secondImage: UIImage? = nil
    
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
        guard let selection else {return}
        Task{
            if let data = try? await selection.loadTransferable(type: Data.self){
                if let uiImage = UIImage(data:data){
                    if(number==2){
                        secondImage = uiImage
                    }
                    else{
                        selectedImage = uiImage
                    }
                   
                    return
                }
                
            }
            


        }
    }
}


struct photopicker: View {
    
    @StateObject private var viewModel = PhotoPickerViewModel()
    @StateObject private var viewModel2 = PhotoPickerViewModel()
    let detector = StillImageDetect()
    var body: some View {
        if let image = viewModel.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width:200, height:200)
                .cornerRadius(10)
        }
        
        if let image2 = viewModel2.secondImage {
            Image(uiImage: image2)
                .resizable()
                .scaledToFit()
                .frame(width:200, height:200)
                .cornerRadius(10)
        }
        
        PhotosPicker(selection: $viewModel.imageSelected){
            Text("Open picture!")
        }
        
        PhotosPicker(selection: $viewModel2.seccondSelected){
            Text("Open seccond picture!")
        }
        
        Button("Compare"){
            if viewModel.selectedImage != nil && viewModel2.secondImage != nil{
                detector.stillImage(stillPic: viewModel.selectedImage!)
                detector.stillImage(stillPic: viewModel2.secondImage!)
            }
            else{
                print("nillvalue")
            }
            print("They are the same!")
        }
    }
}

#Preview {
    photopicker()
}
