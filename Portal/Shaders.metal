//
//  Shaders.metal
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    out.texCoord = in.texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);

    return float4(colorSample);
}

// Portal shader - creates glowing oval effect
fragment float4 portalFragmentShader(ColorInOut in [[stage_in]],
                                     constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    // Calculate distance from center
    float2 centerOffset = in.texCoord - float2(0.5, 0.5);
    float distFromCenter = length(centerOffset * 2.0);

    // Create oval mask (fade at edges)
    float oval = 1.0 - smoothstep(0.85, 1.0, distFromCenter);

    // Portal color based on uniform (we'll use modelMatrix[3][3] as color flag)
    // For now, use texCoord as color indicator
    float isOrange = uniforms.modelMatrix[3][3];
    float3 portalColor;

    if (isOrange > 0.5) {
        // Orange portal
        portalColor = float3(1.0, 0.5, 0.1);
    } else {
        // Blue portal
        portalColor = float3(0.2, 0.5, 1.0);
    }

    // Create glow effect - brighter at edges
    float glow = 1.0 - smoothstep(0.7, 0.95, distFromCenter);
    glow = pow(glow, 2.0) * 1.5;

    // Inner swirl effect
    float swirl = sin(distFromCenter * 10.0 + atan2(centerOffset.y, centerOffset.x) * 3.0) * 0.1 + 0.9;

    // Combine effects
    float3 finalColor = portalColor * glow * swirl;
    float alpha = oval * 0.9; // Semi-transparent

    return float4(finalColor, alpha);
}
