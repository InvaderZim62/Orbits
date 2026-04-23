//
//  ViewController.swift
//  Orbits
//
//  Created by Phil Stern on 4/13/26.
//

import UIKit
import RealityKit

struct Constant {
    static let sunRadius: Float = 0.8
    static let earthRadius: Float = 0.45
    static let moonRadius: Float = 0.3 * earthRadius
    static let sunToEarthDistance: Float = 4.5  // (s/b 0.00256 * sunToEarthDistance)
    static let earthToMoonDistance: Float = 2 * earthRadius
    static let earthRotationFactor: Float = 3  // x moon orbit rate (s/b 27.3)
    static let earthObliquity: Float = 23.44 * .pi / 180  // north pole tilt (actual)
    static let lunarOrbitInclination: Float = 5.14 * .pi / 180  // (actual)
    static let showMoonPath = true
}

class ViewController: UIViewController {
    
    var sun: ModelEntity!
    var earth: ModelEntity!
    var moon: ModelEntity!
    var pastEarthContainerPosition = simd_float3.zero  // relative to sunAnchor
    var pastMoonPosition = simd_float3.zero  // relative to earthAnchor
    var earthOrbitAngle: Float = 0  // orbital angle around the sun
    var moonOrbitAngle: Float = 0  // orbital angle around the earth

    var worldAnchor = AnchorEntity()
    var earthContainer = ModelEntity()  // moves with earth, but stays level (earth's north pole is tiled in container)
    var moonContainer = ModelEntity()  // moves with earth, but tilted by the lunar inclination

    @IBOutlet var arViewCC: ARViewCameraControl!  // my subclass of ARView that includes SceneKit-like camera controls (for nonAR apps, only)

    override func viewDidLoad() {
        super.viewDidLoad()
        
//        arViewCC.environment.background = .color(.lightGray)
        worldAnchor = arViewCC.worldAnchor
        createSolarSystem()
        arViewCC.raiseCameraUp(degrees: 30)  // start off looking slightly down at scene
        setupSunlight()
    }

    // Solar System
    // entity           parent           position w.r.t parent    orientation w.r.t parent
    // --------------   --------------   ----------------------   ---------------------------------------------
    // worldAnchor      n/a              camera position at tap   camera orientation at tap gesture
    // sun              worldAnchor      z = -1.5                 same
    // earthContainer   sun              orbits around center     same
    // earth            earthContainer   center                   North pole tilted (spinning about North pole)
    // moonContainer    earthContainer   center                   tilted by lunarOrbitInclination
    // moon             moonContainer    orbits around center     same (doesn't currently spin)

    private func createSolarSystem() {
        sun = createSphereEntity(radius: Constant.sunRadius, color: .yellow)
        worldAnchor.addChild(sun)
        
//        earth = createSphereEntity(radius: Constant.earthRadius, color: .blue)
        
        earth = try! Entity.loadModel(named: "earth")  // load Blender model (sized to give Xcode radius = 0.45)
        earth.scale *= Constant.earthRadius / 0.45
        let texture = try! TextureResource.load(named: "earth")  // load .png image
        var material = SimpleMaterial()
        material.color = SimpleMaterial.BaseColor(texture: .init(texture))
        earth.model?.materials = [material]
        
        earth.transform.rotation = simd_quatf(angle: -Constant.earthObliquity, axis: [0, 0, 1])  // tilt North pole
        earthContainer.addChild(earth)
        earthContainer.position = [Constant.sunToEarthDistance, 0, 0]
        sun.addChild(earthContainer)
        pastEarthContainerPosition = earthContainer.position
        
        moon = createSphereEntity(radius: Constant.moonRadius, color: .gray)
        moon.position = moonPosition(orbitAngle: 0)  // in moonContainer
        moonContainer.addChild(moon)
        moonContainer.transform.rotation = simd_quatf(angle: Constant.lunarOrbitInclination, axis: [0, 0, 1])  // tilt lunar orbit plane
        earthContainer.addChild(moonContainer)  // moonContainer centered on Earth, but tilted
        pastMoonPosition = moon.position
        
//        let eclipticPlane = createEclipticPlane()  // plane around sun
//        sun.addChild(eclipticPlane)
//
//        let lunarOrbitPlane = createLunarOrbitPlane()
//        moonContainer.addChild(lunarOrbitPlane)
        
        drawEarthPath()
        
        Timer.scheduledTimer(timeInterval: 0.05,
                             target: self,
                             selector: #selector(orbit),
                             userInfo: nil,
                             repeats: true)
    }
    
    @objc func orbit() {
        let deltaEarthAngle: Float = 0.004
        let deltaMoonAngle = 13.37 * deltaEarthAngle

        earthOrbitAngle += deltaEarthAngle
        earthContainer.position = [cos(earthOrbitAngle), 0, -sin(earthOrbitAngle)] * Constant.sunToEarthDistance

        moonOrbitAngle += deltaMoonAngle
        moon.position = moonPosition(orbitAngle: moonOrbitAngle)  // position relative to moonContainer

        // spin earth around north pole
        let transform = Transform(pitch: 0, yaw: Constant.earthRotationFactor * deltaMoonAngle, roll: 0)
        earth.setTransformMatrix(transform.matrix, relativeTo: earth)  // incremental rotation
        
        if Constant.showMoonPath {
            // draw moon's path around Earth, on the fly
            if fmod(moonOrbitAngle, 0.3) > -deltaMoonAngle {  // ~1:5
                let lineSegment = createLine(from: pastMoonPosition, to: moon.position)  // this creates circle around earth
                lineSegment.position = moonContainer.convert(position: lineSegment.position, to: sun)
                sun.addChild(lineSegment)
                pastMoonPosition = moon.position
            }
        }
    }
    
    // moon position within moon container
    private func moonPosition(orbitAngle: Float) -> simd_float3 {
        simd_float3(cos(orbitAngle), 0, -sin(orbitAngle)) * Constant.earthToMoonDistance
    }
    
    private func drawEarthPath() {
        for index in 0..<121 {  // every 3 degrees
            let angle = Float(3 * index) * .pi / 180
            let x = cos(angle) * Constant.sunToEarthDistance
            let z = sin(angle) * Constant.sunToEarthDistance
            let position = simd_float3(x, 0, z)
            let lineSegment = createLine(from: pastEarthContainerPosition, to: position)
            sun.addChild(lineSegment)
            pastEarthContainerPosition = position
        }
    }
    
    // create lines out of boxes
    private func createLine(from start: simd_float3, to end: simd_float3) -> ModelEntity {
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let distance = length(end - start)
        let lineWidth: Float = 0.03

        let lineMesh = MeshResource.generateBox(width: lineWidth, height: lineWidth, depth: distance, cornerRadius: 0)
        let material = UnlitMaterial(color: .gray)  // don't interact with light/shadows
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [material])
        
        lineEntity.orientation = simd_quatf(from: simd_float3(0, 0, 1), to: direction)
        lineEntity.position = midpoint
        
        return lineEntity
    }
    
    private func setupSunlight() {
        // SpotLight allows you to set position (point of origin) and orientation;
        // to get complete coverage, use 3 spotlights (every 120 deg) with 140 deg spread (good overlap)
        addSpotLight(orientation: simd_quatf(angle: 0, axis: [0, 1, 0]))
        addSpotLight(orientation: simd_quatf(angle: 2/3 * .pi, axis: [0, 1, 0]))
        addSpotLight(orientation: simd_quatf(angle: -2/3 * .pi, axis: [0, 1, 0]))
        
        // lighten whole scene a little
        let directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        arViewCC.camera.addChild(directionalLight)
    }
    
    private func addSpotLight(orientation: simd_quatf) {
        let spotlight = SpotLight()
        spotlight.position = sun.position
        spotlight.orientation = orientation
        spotlight.light.intensity = 3000000
        spotlight.light.outerAngleInDegrees = 140  // more then 160 deg starts to diminish shadow
        spotlight.light.attenuationRadius = 6
        spotlight.shadow = SpotLightComponent.Shadow()
        spotlight.shadow?.depthBias = 0.5
        sun.addChild(spotlight)
    }

    private func createSphereEntity(radius: Float, color: UIColor? = nil) -> ModelEntity {
        let sphereEntity = ModelEntity(mesh: .generateSphere(radius: radius))
        if let color {
            let material = SimpleMaterial(color: color, roughness: 1, isMetallic: false)  // roughness makes it more of a matte finish
            sphereEntity.model?.materials = [material]
        } else {
            // default swirl pattern
            sphereEntity.generateCollisionShapes(recursive: false)  // needed for .debugOptions
        }
        return sphereEntity
    }
    
    private func createEclipticPlane() -> ModelEntity {
        let planeEntity = ModelEntity(mesh: .generateBox(size: [10, 0, 10]))
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), roughness: 1, isMetallic: false)
        planeEntity.model?.materials = [material]
        return planeEntity
    }
    
    private func createLunarOrbitPlane() -> ModelEntity {
        let planeEntity = ModelEntity(mesh: .generateBox(size: [3, 0, 3]))
        let material = SimpleMaterial(color: .gray.withAlphaComponent(0.3), roughness: 1, isMetallic: false)
        planeEntity.model?.materials = [material]
        return planeEntity
    }
}
