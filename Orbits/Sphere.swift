//
//  Sphere.swift
//  Orbits
//
//  Created by Phil Stern on 4/25/26.
//

import UIKit
import RealityKit

class Sphere: Entity, HasModel {
    
    init(radius: Float, textureName: String) {
        super.init()
        if let texture = try? TextureResource.load(named: textureName) {  // load .png image
            var material = SimpleMaterial()
            material.color = SimpleMaterial.BaseColor(texture: .init(texture))
            model = ModelComponent(mesh: .generateSphere(radius: radius), materials: [material])
        } else {
            // default swirl pattern
            model = ModelComponent(mesh: .generateSphere(radius: radius), materials: [])
        }
    }
    
    init(radius: Float, color: UIColor? = nil) {
        super.init()
        if let color {
            let material = SimpleMaterial(color: color, roughness: 1, isMetallic: false)  // roughness makes it more of a matte finish
            model = ModelComponent(mesh: .generateSphere(radius: radius), materials: [material])
        } else {
            // default swirl pattern
            model = ModelComponent(mesh: .generateSphere(radius: radius), materials: [])
        }
    }
    
    @MainActor @preconcurrency required init() {
        fatalError("init() has not been implemented")
    }
}
