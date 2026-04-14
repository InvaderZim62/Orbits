//
//  ViewController.swift
//  Orbits
//
//  Created by Phil Stern on 4/13/26.
//

import UIKit
import RealityKit

struct Constant {
    static let sunRadius: Float = 0.9
    static let earthRadius: Float = 0.5
    static let moonRadius: Float = 0.2 // 0.27 * earthRadius
    static let sunToEarthDistance: Float = 3.4
    static let earthToMoonDistance: Float = 1 // 0.00256 * sunToEarthDistance
}

class ViewController: UIViewController {
    
    var earth: Entity!
    var moon: Entity!

    var earthAngle: Float = 0
    var moonAngle: Float = 0

    @IBOutlet var arViewCC: ARViewCameraControl!  // subclass of ARView that includes SceneKit-like camera controls (for nonAR apps, only)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        arViewCC.environment.background = .color(.lightGray)
        let worldAnchor = arViewCC.worldAnchor
        
        let sun = createSphereEntity(radius: Constant.sunRadius, color: .yellow)
        sun.position = [0, 0, 0]
        worldAnchor.addChild(sun)
        
        earth = createSphereEntity(radius: Constant.earthRadius, color: .blue)
        earth.position = [Constant.sunToEarthDistance, 0, 0]
        worldAnchor.addChild(earth)

        moon = createSphereEntity(radius: Constant.moonRadius, color: .gray)
        moon.position = earth.position + [Constant.earthToMoonDistance, 0, 0]
        worldAnchor.addChild(moon)

        let orbitalPlane = createOrbitalPlane()
        orbitalPlane.position = [0, 0, 0]
        worldAnchor.addChild(orbitalPlane)
        
        Timer.scheduledTimer(timeInterval: 0.02,
                             target: self,
                             selector: #selector(orbit),
                             userInfo: nil,
                             repeats: true)
    }

    @objc func orbit() {
        let deltaAngle: Float = 0.005
        
        earthAngle -= deltaAngle
        let earthX = cos(earthAngle) * Constant.sunToEarthDistance
        let earthZ = sin(earthAngle) * Constant.sunToEarthDistance
        earth.position = [earthX, 0, earthZ]
        
        moonAngle -= 13.37 * deltaAngle
        let moonX = cos(moonAngle) * Constant.earthToMoonDistance
        let moonZ = sin(moonAngle) * Constant.earthToMoonDistance
        moon.position = earth.position + [moonX, 0, moonZ]
    }
    
    private func createSphereEntity(radius: Float, color: UIColor) -> ModelEntity {
        let material = SimpleMaterial(color: color, isMetallic: false)
        let sphereEntity = ModelEntity(mesh: .generateSphere(radius: radius))
        sphereEntity.model?.materials = [material]  // default checkerboard pattern
        sphereEntity.generateCollisionShapes(recursive: false)  // needed for .debugOptions
        return sphereEntity
    }
    
    private func createOrbitalPlane() -> ModelEntity {
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), isMetallic: false)
        let planeEntity = ModelEntity(mesh: .generateBox(size: [10, 0, 10]))
        planeEntity.model?.materials = [material]
        planeEntity.generateCollisionShapes(recursive: false)
        return planeEntity
    }
}
