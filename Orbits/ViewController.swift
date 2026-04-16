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
//    static let earthObliquity: Float = 23.44 * .pi / 180  // north pole tilt
    static let earthObliquity: Float = 30 * .pi / 180  // exaggerated
//    static let lunarOrbitInclination: Float = 5.14 * .pi / 180
    static let lunarOrbitInclination: Float = 20 * .pi / 180  // exaggerated
    static let showMoonPath = true
}

class ViewController: UIViewController {
    
    var earth: Entity!
    var moon: Entity!
    var pastPosition = simd_float3.zero  // relative to sunAnchor
    var pastMoonPosition = simd_float3.zero  // relative to earthAnchor
    var earthAngle: Float = 0  // orbital angle around the sun
    var moonAngle: Float = 0  // orbital angle around the earth

    var sunAnchor = AnchorEntity()
    var earthAnchor = AnchorEntity()

    @IBOutlet var arViewCC: ARViewCameraControl!  // subclass of ARView that includes SceneKit-like camera controls (for nonAR apps, only)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        arViewCC.environment.background = .color(.lightGray)
        sunAnchor = arViewCC.worldAnchor
        arViewCC.scene.addAnchor(earthAnchor)
        
        let sun = createSphereEntity(radius: Constant.sunRadius, color: .yellow)
        sun.position = [0, 0, 0]
        sunAnchor.addChild(sun)
        
        earth = createSphereEntity(radius: Constant.earthRadius)//, color: .blue)
        earth.transform.rotation = simd_quatf(angle: -Constant.earthObliquity, axis: [0, 0, 1])  // tilt North pole
        earthAnchor.addChild(earth)
        earthAnchor.position = [Constant.sunToEarthDistance, 0, 0]
        pastPosition = earthAnchor.position

        moon = createSphereEntity(radius: Constant.moonRadius, color: .gray)
        moon.position = earthToMoonPosition(orbitAngle: 0)
        earthAnchor.addChild(moon)
        pastMoonPosition = moon.position

        let eclipticPlane = createEclipticPlane()  // plane around sun
        eclipticPlane.position = [0, 0, 0]
        sunAnchor.addChild(eclipticPlane)

        let lunarOrbitPlane = createLunarOrbitPlane()
        lunarOrbitPlane.transform.rotation = simd_quatf(angle: Constant.lunarOrbitInclination, axis: [0, 0, 1])
        lunarOrbitPlane.position = [0, 0, 0]
        earthAnchor.addChild(lunarOrbitPlane)

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

        earthAngle += deltaEarthAngle
        let earthX = cos(earthAngle) * Constant.sunToEarthDistance
        let earthZ = -sin(earthAngle) * Constant.sunToEarthDistance
        earthAnchor.position = [earthX, 0, earthZ]
        
        moonAngle += deltaMoonAngle
        moon.position = earthToMoonPosition(orbitAngle: moonAngle)
        
        if Constant.showMoonPath {
            // draw moon's path around Earth, on the fly
            if fmod(moonAngle, 0.3) > -deltaMoonAngle {  // ~1:5
                let lineSegment = createLine(from: pastMoonPosition, to: moon.position)
                earthAnchor.addChild(lineSegment)
                pastMoonPosition = moon.position
            }
        }
    }
    
    // moon position relative to earthAnchor (which moves earth)
    private func earthToMoonPosition(orbitAngle: Float) -> simd_float3 {
        simd_float3(cos(Constant.lunarOrbitInclination * cos(orbitAngle)) * cos(orbitAngle),
                    sin(Constant.lunarOrbitInclination * cos(orbitAngle)),
                    -cos(Constant.lunarOrbitInclination * cos(orbitAngle)) * sin(orbitAngle)) * Constant.earthToMoonDistance
    }
    
    private func drawEarthPath() {
        for index in 0..<361 {
            let angle = Float(index) * .pi / 180
            let x = cos(angle) * Constant.sunToEarthDistance
            let z = sin(angle) * Constant.sunToEarthDistance
            let position = simd_float3(x, 0, z)
            let lineSegment = createLine(from: pastPosition, to: position)
            sunAnchor.addChild(lineSegment)
            pastPosition = position
        }
    }
    
    // create lines out of boxes
    private func createLine(from start: simd_float3, to end: simd_float3) -> ModelEntity {
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let distance = length(end - start)
        let lineWidth: Float = 0.05
        
        let lineMesh = MeshResource.generateBox(width: lineWidth, height: lineWidth, depth: distance, cornerRadius: lineWidth / 2)
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [material])
        
        lineEntity.orientation = simd_quatf(from: simd_float3(0, 0, 1), to: direction)
        lineEntity.position = midpoint
        
        return lineEntity
    }
    
    private func createSphereEntity(radius: Float, color: UIColor? = nil) -> ModelEntity {
        let sphereEntity = ModelEntity(mesh: .generateSphere(radius: radius))
        if let color {
            let material = SimpleMaterial(color: color, isMetallic: false)
            sphereEntity.model?.materials = [material]
        } else {
            // default swirl pattern
            sphereEntity.generateCollisionShapes(recursive: false)  // needed for .debugOptions
        }
        return sphereEntity
    }
    
    private func createEclipticPlane() -> ModelEntity {
        let planeEntity = ModelEntity(mesh: .generateBox(size: [10, 0, 10]))
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), isMetallic: false)
        planeEntity.model?.materials = [material]
        return planeEntity
    }
    
    private func createLunarOrbitPlane() -> ModelEntity {
        let planeEntity = ModelEntity(mesh: .generateBox(size: [3, 0, 3]))
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), isMetallic: false)
        planeEntity.model?.materials = [material]
        return planeEntity
    }
}
