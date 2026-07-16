//
//  LiquidGlassVertex.metal
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-06.
//

#include <metal_stdlib>
using namespace metal;

// Vertex output: Passed to fragment.
struct VertexOutput {
    float4 position [[position]];      // Clipped NDC
    half2 uv;                          // Interpolated UVs
};

// Vertex shader: Hardcoded fullscreen quad.
vertex VertexOutput fullscreenQuad(uint vertexID [[vertex_id]]) {
    VertexOutput output;

    // Unpacked quad: 0=BL, 1=BR, 2=TL, 3=TR (triangle strip order)
    float2 positions[4] = {
        float2(-1.0f, -1.0f),  // Bottom-left
        float2( 1.0f, -1.0f),  // Bottom-right
        float2(-1.0f,  1.0f),  // Top-left
        float2( 1.0f,  1.0f)   // Top-right
    };

    float2 uvs[4] = {
        float2(0.0f, 0.0f),
        float2(1.0f, 0.0f),
        float2(0.0f, 1.0f),
        float2(1.0f, 1.0f)
    };

    output.position = float4(positions[vertexID], 0.0f, 1.0f);
    output.uv = half2(uvs[vertexID]);
    return output;
}
