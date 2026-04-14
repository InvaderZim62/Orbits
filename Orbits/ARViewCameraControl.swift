//
//  ARViewCameraControl.swift
//
//  Created by Phil Stern on 4/13/26.
//
//  RealityKit doesn't have .allowsCameraControl like SceneKit does.
//  This class includes gesture recognizers to mimic it.
//  This class is for non-augmented reality (not using device's camera).
//

import UIKit
import RealityKit

class ARViewCameraControl: ARView {
    
    let worldAnchor = AnchorEntity()
    let camera = PerspectiveCamera()
    var cameraOffset = simd_float3(0, 0, 24)  // camera position in camera coordinates

    @MainActor @preconcurrency required dynamic init?(coder decoder: NSCoder) {  // called from Storyboard
        super.init(coder: decoder)
        
        cameraMode = .nonAR  // don't use iPhone camera
//        debugOptions = [.showWorldOrigin, .showPhysics]  // show axes - requires entity.generateCollisionShapes(recursive:)

        camera.orientation = camera.orientation.rotatedBy(deltaPitch: -0.32 * .pi, deltaYaw: 0, deltaRoll: 0)
        camera.position = convertVectorFromLocalToWorld(vector: cameraOffset, camera.orientation)
        worldAnchor.addChild(camera)
        scene.addAnchor(worldAnchor)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(pan)
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinch)
        
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation))
        addGestureRecognizer(rotation)
    }
    
    @MainActor @preconcurrency required dynamic init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    @objc func handlePan(recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)
        
        if recognizer.numberOfTouches == 1 {
            // rotate camera
            let deltaRight = Float(translation.x / 130)
            let deltaUp = Float(-translation.y / 130)
            
            // deltaRight rotates the scene/camera about the world y-axis;
            // deltaUp rotates the scene/camera about the camera x-axis;
            // deltaRight must be converted to camera coordinates before adding to deltaUp
            let deltaCamera = convertVectorFromWorldToLocal(vector: simd_float3(0, -deltaRight, 0), camera.orientation)
            camera.orientation = camera.orientation.rotatedBy(deltaPitch: deltaCamera.x + deltaUp,
                                                              deltaYaw: deltaCamera.y,
                                                              deltaRoll: deltaCamera.z)
        } else if recognizer.numberOfTouches == 2 {
            // offset camera
            let deltaRight = Float(translation.x / 75)
            let deltaUp = Float(-translation.y / 75)
            
            // deltas move the scene/camera in camera coordinates
            let deltaPosition = simd_float3(deltaRight, deltaUp, 0)
            cameraOffset -= deltaPosition
        }
        
        camera.position = convertVectorFromLocalToWorld(vector: cameraOffset, camera.orientation)
        recognizer.setTranslation(.zero, in: recognizer.view)
    }
    
    @objc func handlePinch(recognizer: UIPinchGestureRecognizer) {
        // pinching moves the camera forward/aft (ie. camera z-direction)
        cameraOffset.z /= Float(recognizer.scale)
        camera.position = convertVectorFromLocalToWorld(vector: cameraOffset, camera.orientation)
        recognizer.scale = 1
    }
    
    @objc func handleRotation(recognizer: UIRotationGestureRecognizer) {
        // rotation rotates the scene/camera about the camera z-axis (ie. center of screen)
        let deltaRoll = Float(recognizer.rotation)
        camera.orientation = camera.orientation.rotatedBy(deltaPitch: 0, deltaYaw: 0, deltaRoll: deltaRoll)
        let deltaQuat = simd_quatf(angle: deltaRoll, axis: [0, 0, 1])
        cameraOffset = convertVectorFromWorldToLocal(vector: cameraOffset, deltaQuat)
        recognizer.rotation = 0
    }
    
    private func convertVectorFromLocalToWorld(vector: simd_float3, _ quat: simd_quatf) -> simd_float3 {
        quat.act(vector)
    }
    
    private func convertVectorFromWorldToLocal(vector: simd_float3, _ quat: simd_quatf) -> simd_float3 {
        quat.inverse.act(vector)
    }
}

extension simd_quatf {
    // incrementally rotate quaternion
    func rotatedBy(deltaPitch: Float, deltaYaw: Float, deltaRoll: Float) -> simd_quatf {
        let quat = self.vector
        
        // quaternion rates (aeronautical standard, except: p -> q, q -> r, r -> p)
        let deltaQw = (-quat.x * deltaPitch - quat.y * deltaYaw - quat.z * deltaRoll) / 2
        let deltaQx = ( quat.w * deltaPitch - quat.z * deltaYaw + quat.y * deltaRoll) / 2
        let deltaQy = ( quat.z * deltaPitch + quat.w * deltaYaw - quat.x * deltaRoll) / 2
        let deltaQz = (-quat.y * deltaPitch + quat.x * deltaYaw + quat.w * deltaRoll) / 2
        
        // integrate quaternion rates
        let qw = quat.w + deltaQw
        let qx = quat.x + deltaQx
        let qy = quat.y + deltaQy
        let qz = quat.z + deltaQz
        
        // normalize quaternions to prevent error growth
        let rotatedQuat = simd_normalize(simd_quatf(ix: qx, iy: qy, iz: qz, r: qw))
        
        return rotatedQuat
    }
}
