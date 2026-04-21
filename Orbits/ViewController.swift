//
//  ViewController.swift
//  Orbits
//
//  Created by Phil Stern on 4/13/26.
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
    
    var sun: ModelEntity!
    var earth: ModelEntity!
    var moon: ModelEntity!
    var isSolarSystemCreated = false
    var pastPosition = simd_float3.zero  // relative to sunAnchor
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
    
    // add new sphere in front of camera (fixed in space)
    // note: models can't be added in viewDidLoad or viewWillAppear
    @objc private func handleTap(recognizer: UITapGestureRecognizer) {
        worldAnchor.transform = arView.cameraTransform
        guard !isSolarSystemCreated else { return }  // only add it once
        arView.scene.addAnchor(worldAnchor)
        createSolarSystem()
        isSolarSystemCreated = true
    }

    private func createSolarSystem() {
        sun = createSphereEntity(radius: Constant.sunRadius, color: .yellow)
        sun.position.z = -1.5
        worldAnchor.addChild(sun)
        
        earth = createSphereEntity(radius: Constant.earthRadius, color: .blue)
        
        // pws: can't figure out how to scale the blender model
//        earth = try! Entity.loadModel(named: "earth")  // load Blender model
//        let texture = try! TextureResource.load(named: "earth")  // load .png image
//        var material = SimpleMaterial()
//        material.color = SimpleMaterial.BaseColor(texture: .init(texture))
//        earth.model?.materials = [material]
        
        earth.transform.rotation = simd_quatf(angle: -Constant.earthObliquity, axis: [0, 0, 1])  // tilt North pole
        earthContainer.addChild(earth)
        earthContainer.position = sun.position + [Constant.sunToEarthDistance, 0, 0]
        worldAnchor.addChild(earthContainer)
        pastPosition = earthContainer.position

        moon = createSphereEntity(radius: Constant.moonRadius, color: .gray)
        moon.position = moonPosition(orbitAngle: 0)  // in moonContainer
        moonContainer.addChild(moon)
        moonContainer.transform.rotation = simd_quatf(angle: Constant.lunarOrbitInclination, axis: [0, 0, 1])  // tilt lunar orbit plane
        earthContainer.addChild(moonContainer)  // moonContainer centered on Earth, but tilted
        pastMoonPosition = moon.position

        setupSunlight()
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
        earthContainer.position = sun.position + [cos(earthOrbitAngle), 0, -sin(earthOrbitAngle)] * Constant.sunToEarthDistance

        moonOrbitAngle += deltaMoonAngle
        moon.position = moonPosition(orbitAngle: moonOrbitAngle)  // position relative to moonContainer

        // spin earth around north pole
        let transform = Transform(pitch: 0, yaw: Constant.earthRotationFactor * deltaMoonAngle, roll: 0)
        earth.setTransformMatrix(transform.matrix, relativeTo: earth)  // incremental rotation
        
        if Constant.showMoonPath {
            // draw moon's path around Earth, on the fly
            if fmod(moonOrbitAngle, 0.3) > -deltaMoonAngle {  // ~1:5
                let lineSegment = createLine(from: pastMoonPosition, to: moon.position)
                lineSegment.position = moonContainer.convert(position: lineSegment.position, to: worldAnchor)
                worldAnchor.addChild(lineSegment)
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
            let position = sun.position + simd_float3(x, 0, z)
            let lineSegment = createLine(from: pastPosition, to: position)
            worldAnchor.addChild(lineSegment)
            pastPosition = position
        }
    }
    
    // create lines out of boxes
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
        directionalLight.light.intensity = 2000
        directionalLight.transform = arView.cameraTransform  // update in session(didUpdate:), below
        worldAnchor.addChild(directionalLight)
    }
    
    private func addSpotLight(orientation: simd_quatf) {
        let spotlight = SpotLight()
        spotlight.position = sun.position
        spotlight.orientation = orientation
        spotlight.light.intensity = 1000000 * Constant.scale
        spotlight.light.outerAngleInDegrees = 140  // more then 160 deg starts to diminish shadow
        spotlight.light.attenuationRadius = 6
        spotlight.shadow = SpotLightComponent.Shadow()
        spotlight.shadow?.depthBias = 0.5
        worldAnchor.addChild(spotlight)
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

extension ViewController: ARSessionDelegate {  // requires arView.session.delegate = self
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // keep light emanating from camera
        directionalLight.transform = arView.cameraTransform
    }
}
