//
//  Camera.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "Camera.h"

Camera camera_create(vector_float3 position)
{
    return (Camera) {
        .position = position,
        .pitch = 0.0f,
        .yaw = 0.0f
    };
}

vector_float3 camera_up(void)
{
    return (vector_float3){0.0f, 1.0f, 0.0f};
}

vector_float3 camera_forward(Camera camera)
{
    float cosPitch = cosf(camera.pitch);
    float sinPitch = sinf(camera.pitch);
    float cosYaw = cosf(camera.yaw);
    float sinYaw = sinf(camera.yaw);
    
    return (vector_float3) {
        sinYaw * cosPitch,
        sinPitch,
        -cosYaw * cosPitch
    };
}

vector_float3 camera_right(Camera camera)
{
    vector_float3 forward = camera_forward(camera);
    vector_float3 up = camera_up();
    return simd_normalize(simd_cross(forward, up));
}

matrix_float4x4 camera_view_matrix(Camera camera)
{
    vector_float3 forward = camera_forward(camera);
    vector_float3 right = camera_right(camera);
    vector_float3 up = camera_up();
    
    vector_float3 target = camera.position + forward;
    
    vector_float3 zaxis = simd_normalize(camera.position - target);
    vector_float3 xaxis = simd_normalize(simd_cross(up, zaxis));
    vector_float3 yaxis = simd_cross(zaxis, xaxis);
    
    return (matrix_float4x4) {{
        { xaxis.x, yaxis.x, zaxis.x, 0 },
        { xaxis.y, yaxis.y, zaxis.y, 0 },
        { xaxis.z, yaxis.z, zaxis.z, 0 },
        { -simd_dot(xaxis, camera.position), -simd_dot(yaxis, camera.position), -simd_dot(zaxis, camera.position), 1 }
    }};
}
