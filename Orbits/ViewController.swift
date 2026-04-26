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
    static let showMoonPath = false
}

class ViewController: UIViewController {
    
    var sun: SphereEntity!
    var earth: SphereEntity!
    var moon: SphereEntity!
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
    // camera           worldAnchor      z = 30                   level
    // sun              worldAnchor      centered                 level
    // earthContainer   sun              orbit around sun         level
    // earth            earthContainer   centered                 North pole tilted (spinning about North pole)
    // moonContainer    earthContainer   centered                 tilted by lunarOrbitInclination
    // moon             moonContainer    orbit around container   level (doesn't currently spin)
    
    // Note: containers are used to simplify orbital equations; objects are either centered or have simple 2D orbits in their containers

    private func createSolarSystem() {
        sun = SphereEntity(radius: Constant.sunRadius, color: .yellow)
        sun.setParent(worldAnchor)

        earthContainer.position = [Constant.sunToEarthDistance, 0, 0]  // initial position (updated in updateOrbit)
        earthContainer.setParent(sun)

        earth = SphereEntity(radius: Constant.earthRadius, textureName: "earthTexture")
        earth.transform.rotation = simd_quatf(angle: -Constant.earthObliquity, axis: [0, 0, 1])  // tilt North pole
        earth.setParent(earthContainer)

        moonContainer.transform.rotation = simd_quatf(angle: Constant.lunarOrbitInclination, axis: [0, 0, 1])  // tilt lunar orbit plane
        moonContainer.setParent(earthContainer)

        moon = SphereEntity(radius: Constant.moonRadius, color: .gray)
        moon.position = [Constant.earthToMoonDistance, 0, 0]  // initial position (updated in updateOrbit)
        moon.setParent(moonContainer)

        pastEarthContainerPosition = earthContainer.position
        pastMoonPosition = moon.position

//        let eclipticPlane = createEclipticPlane()  // plane around sun
//        sun.addChild(eclipticPlane)
//
//        let lunarOrbitPlane = createLunarOrbitPlane()
//        moonContainer.addChild(lunarOrbitPlane)

        drawEarthContainerPath()
        
        Timer.scheduledTimer(timeInterval: 0.05,
                             target: self,
                             selector: #selector(updateOrbits),
                             userInfo: nil,
                             repeats: true)
    }
    
    // move earthContainer around sun and moon around moonContainer
    @objc func updateOrbits() {
        let deltaEarthAngle: Float = 0.004
        let deltaMoonAngle = 13.37 * deltaEarthAngle

        earthOrbitAngle += deltaEarthAngle
        earthContainer.position = orbitPosition(angle: earthOrbitAngle, radius: Constant.sunToEarthDistance)  // position relative to sun

        moonOrbitAngle += deltaMoonAngle
        moon.position = orbitPosition(angle: moonOrbitAngle, radius: Constant.earthToMoonDistance)  // position relative to moonContainer

        // spin earth around north pole
        let transform = Transform(pitch: 0, yaw: Constant.earthRotationFactor * deltaMoonAngle, roll: 0)
        earth.setTransformMatrix(transform.matrix, relativeTo: earth)  // incremental rotation
        
        if Constant.showMoonPath {
            // draw moon's path around Earth, on the fly
            if fmod(moonOrbitAngle, 0.3) > -deltaMoonAngle {  // ~1:5
                let lineSegment = createLine(from: pastMoonPosition, to: moon.position)
                lineSegment.position = moonContainer.convert(position: lineSegment.position, to: sun)
                sun.addChild(lineSegment)
                pastMoonPosition = moon.position
            }
        }
    }
    
    private func drawEarthContainerPath() {
        for index in 0..<121 {  // every 3 degrees
            let angle = Float(3 * index) * .pi / 180
            let earthContainerPosition = orbitPosition(angle: angle, radius: Constant.sunToEarthDistance)
            let lineSegment = createLine(from: pastEarthContainerPosition, to: earthContainerPosition)
            sun.addChild(lineSegment)
            pastEarthContainerPosition = earthContainerPosition
        }
    }

    // 2D circular orbit
    private func orbitPosition(angle: Float, radius: Float) -> simd_float3 {
        simd_float3(cos(angle), 0, -sin(angle)) * radius
    }

    // create lines out of boxes
    // based on: https://stackoverflow.com/a/78905408 (part 3.)
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
        spotlight.light.innerAngleInDegrees = 140
        spotlight.light.outerAngleInDegrees = 140  // more than 160 deg starts to diminish shadow
        spotlight.light.attenuationRadius = 6
        spotlight.shadow = SpotLightComponent.Shadow()
        spotlight.shadow?.depthBias = 0.5
        sun.addChild(spotlight)
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
