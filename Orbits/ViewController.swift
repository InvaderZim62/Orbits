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
    var pastPosition = simd_float3.zero
//    var pastMoonPosition = simd_float3.zero
    var earthAngle: Float = 0
    var moonAngle: Float = 0

    var worldAnchor = AnchorEntity()

    @IBOutlet var arViewCC: ARViewCameraControl!  // subclass of ARView that includes SceneKit-like camera controls (for nonAR apps, only)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        arViewCC.environment.background = .color(.lightGray)
        worldAnchor = arViewCC.worldAnchor
        
        let sun = createSphereEntity(radius: Constant.sunRadius, color: .yellow)
        sun.position = [0, 0, 0]
        worldAnchor.addChild(sun)
        
        earth = createSphereEntity(radius: Constant.earthRadius, color: .blue)
        earth.position = [Constant.sunToEarthDistance, 0, 0]
        pastPosition = earth.position
        worldAnchor.addChild(earth)

        moon = createSphereEntity(radius: Constant.moonRadius, color: .gray)
        moon.position = earth.position + [Constant.earthToMoonDistance, 0, 0]
//        pastMoonPosition = moon.position
        worldAnchor.addChild(moon)

        let orbitalPlane = createOrbitalPlane()
        orbitalPlane.position = [0, 0, 0]
        worldAnchor.addChild(orbitalPlane)
        
        drawEarthPath()
        
        Timer.scheduledTimer(timeInterval: 0.02,
                             target: self,
                             selector: #selector(orbit),
                             userInfo: nil,
                             repeats: true)
    }
    
    @objc func orbit() {
        let deltaEarthAngle: Float = 0.005
        let deltaMoonAngle = 13.37 * deltaEarthAngle

        earthAngle -= deltaEarthAngle
        let earthX = cos(earthAngle) * Constant.sunToEarthDistance
        let earthZ = sin(earthAngle) * Constant.sunToEarthDistance
        earth.position = [earthX, 0, earthZ]
        
        moonAngle -= deltaMoonAngle
        let moonX = cos(moonAngle) * Constant.earthToMoonDistance
        let moonZ = sin(moonAngle) * Constant.earthToMoonDistance
        moon.position = earth.position + [moonX, 0, moonZ]
        
//        // draw moon's path on the fly
//        if fmod(moonAngle, 0.3) > -deltaMoonAngle {  // ~1:5
//            drawLine(from: pastMoonPosition, to: moon.position)
//            pastMoonPosition = moon.position
//        }
    }
    
    private func drawEarthPath() {
        for index in 0..<361 {
            let angle = Float(index) * .pi / 180
            let x = cos(angle) * Constant.sunToEarthDistance
            let z = sin(angle) * Constant.sunToEarthDistance
            let position = simd_float3(x, 0, z)
            drawLine(from: pastPosition, to: position)
            pastPosition = position
        }
    }
    
    // create lines out of boxes
    private func drawLine(from start: simd_float3, to end: simd_float3) {
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let distance = length(end - start)
        let lineWidth: Float = 0.05
        
        let lineMesh = MeshResource.generateBox(width: lineWidth, height: lineWidth, depth: distance, cornerRadius: lineWidth / 2)
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [material])
        
        lineEntity.orientation = simd_quatf(from: simd_float3(0, 0, 1), to: direction)
        lineEntity.position = midpoint
        
        worldAnchor.addChild(lineEntity)
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
