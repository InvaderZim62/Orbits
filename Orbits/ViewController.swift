//
//  ViewController.swift
//  Orbits
//
//  Created by Phil Stern on 4/13/26.
//
//  To do...
//

import UIKit
import RealityKit
import ARKit  // needed for session(didUpdate:)

struct Constant {
    static let scale: Float = 0.2
    static let sunRadius: Float = 0.8 * scale
    static let earthRadius: Float = 0.45 * scale
    static let moonRadius: Float = 0.3 * earthRadius
    static let sunToEarthDistance: Float = 4.5 * scale  // (s/b 0.00256 * sunToEarthDistance)
    static let earthToMoonDistance: Float = 2 * earthRadius
    static let earthRotationFactor: Float = 3  // x moon orbit rate (s/b 27.3)
    static let earthObliquity: Float = 23.44 * .pi / 180  // north pole tilt (actual)
    static let lunarOrbitInclination: Float = 5.14 * .pi / 180  // (actual)
    static let showMoonPath = false
}

class ViewController: UIViewController {
    
    var sun: Sphere!
    var earth: Sphere!
    var moon: Sphere!
    var isSolarSystemCreated = false
    var pastEarthContainerPosition = simd_float3.zero  // relative to sunAnchor
    var pastMoonPosition = simd_float3.zero  // relative to earthAnchor
    var earthOrbitAngle: Float = 0  // orbital angle around the sun
    var moonOrbitAngle: Float = 0  // orbital angle around the earth

    var worldAnchor = AnchorEntity()
    var earthContainer = ModelEntity()  // moves with earth, but stays level (earth's north pole is tiled in container)
    var moonContainer = ModelEntity()  // moves with earth, but tilted by the lunar inclination
    let directionalLight = DirectionalLight()  // moves with camera, to add extra light to whole scene

    @IBOutlet var arView: ARView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView.session.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        arView.addGestureRecognizer(tap)
    }
    
    // move solar system in front of camera
    // note: models can't be added in viewDidLoad or viewWillAppear
    @objc private func handleTap(recognizer: UITapGestureRecognizer) {
        worldAnchor.transform = arView.cameraTransform  // re-position worldAnchor after every tap
        
        guard !isSolarSystemCreated else { return }  // only create solar system once
        arView.scene.addAnchor(worldAnchor)
        createSolarSystem()
        isSolarSystemCreated = true
    }

    // Solar System
    // entity           parent           position w.r.t parent    orientation w.r.t parent
    // --------------   --------------   ----------------------   ---------------------------------------------
    // worldAnchor      n/a              camera position at tap   camera orientation at tap gesture
    // sun              worldAnchor      z = -1.5                 level
    // earthContainer   sun              orbit around sun         level
    // earth            earthContainer   centered                 North pole tilted (spinning about North pole)
    // moonContainer    earthContainer   centered                 tilted by lunarOrbitInclination
    // moon             moonContainer    orbit around container   level (doesn't currently spin)
    
    // Note: containers are used to simplify orbital equations; objects are either centered or have simple 2D orbits in their containers
    
    private func createSolarSystem() {
        sun = Sphere(radius: Constant.sunRadius, color: .yellow)
        sun.position.z = -1.5
        sun.setParent(worldAnchor)

        earthContainer.position = [Constant.sunToEarthDistance, 0, 0]  // initial position (updated in updateOrbit)
        earthContainer.setParent(sun)

        earth = Sphere(radius: Constant.earthRadius, textureName: "earthTexture")
        earth.transform.rotation = simd_quatf(angle: -Constant.earthObliquity, axis: [0, 0, 1])  // tilt North pole
        earth.setParent(earthContainer)

        moonContainer.transform.rotation = simd_quatf(angle: Constant.lunarOrbitInclination, axis: [0, 0, 1])  // tilt lunar orbit plane
        moonContainer.setParent(earthContainer)

        moon = Sphere(radius: Constant.moonRadius, color: .gray)
        moon.position = [Constant.earthToMoonDistance, 0, 0]  // initial position (updated in updateOrbit)
        moon.setParent(moonContainer)

        pastEarthContainerPosition = earthContainer.position
        pastMoonPosition = moon.position

        setupSunlight()
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
        let lineWidth: Float = 0.03 * Constant.scale
        
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
        directionalLight.light.intensity = 2000  // orientation set in session(didUpdate:), below
        worldAnchor.addChild(directionalLight)
    }
    
    private func addSpotLight(orientation: simd_quatf) {
        let spotlight = SpotLight()
        spotlight.orientation = orientation
        spotlight.light.intensity = 1000000 * Constant.scale
        spotlight.light.innerAngleInDegrees = 140
        spotlight.light.outerAngleInDegrees = 140  // more then 160 deg starts to diminish shadow
        spotlight.light.attenuationRadius = 6
        spotlight.shadow = SpotLightComponent.Shadow()
        spotlight.shadow?.depthBias = 0.5
        sun.addChild(spotlight)
    }
}

extension ViewController: ARSessionDelegate {  // requires ARKit and arView.session.delegate = self
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // when turning camera, camera orientation = yaw angle (for example), causing light to point in that direction;
        // after tap sets worldAnchor to camera transform, both worldAnchor and camera orientation = yaw angle;
        // if setting light orientation to camera, light strikes scene from yaw angle, rather then from camera;
        // use identity transform entity to get camera relative to world, so light oriented from camera to world
        
        // keep light pointing in camera direction
        directionalLight.transform = Entity().convert(transform: arView.cameraTransform, to: worldAnchor)
    }
}

