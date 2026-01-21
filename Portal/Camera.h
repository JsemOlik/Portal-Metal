//
//  Camera.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#ifndef Camera_h
#define Camera_h

#import <simd/simd.h>

typedef struct {
    vector_float3 position;
    float pitch;  // rotation around X axis (up/down)
    float yaw;    // rotation around Y axis (left/right)
} Camera;

Camera camera_create(vector_float3 position);
matrix_float4x4 camera_view_matrix(Camera camera);
vector_float3 camera_forward(Camera camera);
vector_float3 camera_right(Camera camera);
vector_float3 camera_up(void);

#endif /* Camera_h */
