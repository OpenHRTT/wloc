//
//  LiquidGlassFragment.metal
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-05.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

#define PI M_PI_F

// Refractive indices for chromatic dispersion (simulating glass-like prismatic effects)
constant float refractiveIndexRed = 1.0f - 0.02f;   // Red channel (slightly lower for dispersion)
constant float refractiveIndexGreen = 1.0f;         // Green channel (neutral)
constant float refractiveIndexBlue = 1.0f + 0.02f;  // Blue channel (slightly higher for dispersion)

// Vertex output: Position (NDC) and UVs [0,1]
struct VertexOutput {
    float4 position [[position]];
    half2 uv;
};

// Maximum number of rectangles (must match Swift side)
constant int maxRectangles = 16;

// Uniforms: Packed struct for Swift/Metal buffer binding
struct ShaderUniforms {
    float2 resolution;               // Viewport resolution (pixels)
    float contentsScale;             // Scale factor for resolution independence
    float2 touchPoint;               // Touch position in points (upper-left origin)
    float shapeMergeSmoothness;      // Smooth min blend factor (higher = softer morph)
    float cornerRadius;              // Rounding radius for rectangle corners
    float cornerRoundnessExponent;   // Superellipse exponent for corner sharpness (higher = sharper)
    float4 materialTint;             // RGBA tint for glass color
    float glassThickness;            // Simulated thickness (pixels) for refraction depth
    float refractiveIndex;           // Base refractive index of glass
    float dispersionStrength;        // Chromatic aberration intensity
    float fresnelDistanceRange;      // Edge distance over which Fresnel builds
    float fresnelIntensity;          // Overall Fresnel reflection strength
    float fresnelEdgeSharpness;      // Power for Fresnel falloff hardness
    float glareDistanceRange;        // Edge distance for glare highlights
    float glareAngleConvergence;     // Angle-based glare focusing
    float glareOppositeSideBias;     // Multiplier for glare on far side of normal
    float glareIntensity;            // Overall glare highlight strength
    float glareEdgeSharpness;        // Power for glare falloff hardness
    float glareDirectionOffset;      // Angular offset for glare direction
    int rectangleCount;              // Number of active rectangles
    float4 rectangles[maxRectangles]; // Array of rectangles (x, y, width, height) in points, upper-left origin
};

// Constant linear sampler for texture lookups (bilinear filtering, no wrap)
constant sampler textureSampler(
    filter::linear,
    mag_filter::linear,
    min_filter::linear,
    address::clamp_to_edge
);

// =============================================================================
// Signed Distance Field (SDF) Primitives and Operations
// SDFs return signed distance: >0 outside, <0 inside, 0 on surface.
// =============================================================================

// Circle SDF: Distance from center minus radius
float circleSDF(float2 point, float radius) {
    return length(point) - radius;
}

// Superellipse SDF: Generalized superellipse for organic shapes.
// Returns float3: x=distance, yz=gradient for normals.
// Uses segment approximation (24 steps) for boundary evaluation.
float3 superellipseSDF(float2 point, float scale, float exponent, constant ShaderUniforms& uniforms) {
    point /= scale;
    float2 signedPoint = sign(point);
    float2 absPoint = abs(point);
    float sumPowers = pow(absPoint.x, exponent) + pow(absPoint.y, exponent);
    float2 gradient = signedPoint * pow(absPoint, float2(exponent - 1.0f)) * pow(sumPowers, 1.0f / exponent - 1.0f);

    // Skip the loop entirely
//    float distance = pow(sumPowers, 1.0f / exponent) - 1.0f;
//    return float3(distance * scale, gradient);

    // Abs and swap for quadrant handling
    point = abs(point);
    if (point.y > point.x) {
        point = point.yx;
    }
    exponent = 2.0f / exponent;
    float sideSign = 1.0f;
    float minDistanceSquared = 1e20f;
    const int segmentCount = 24;
    float2 previousQuadrantPoint = float2(1.0f, 0.0f);
    for (int i = 1; i < segmentCount; ++i) {
        float segmentParam = float(i) / float(segmentCount - 1);
        float2 quadrantPoint = float2(
            pow(cos(segmentParam * PI / 4.0f), exponent),
            pow(sin(segmentParam * PI / 4.0f), exponent)
        );
        float2 pointA = point - previousQuadrantPoint;
        float2 pointB = quadrantPoint - previousQuadrantPoint;
        float2 perpendicular = pointA - pointB * clamp(dot(pointA, pointB) / dot(pointB, pointB), 0.0f, 1.0f);
        float distSq = dot(perpendicular, perpendicular);
        if (distSq < minDistanceSquared) {
            minDistanceSquared = distSq;
            sideSign = pointA.x * pointB.y - pointA.y * pointB.x;
        }
        previousQuadrantPoint = quadrantPoint;
    }
    return float3(sqrt(minDistanceSquared) * sign(sideSign) * scale, gradient);
}

// Superellipse corner SDF: For smooth, parametric rounding in rectangles.
float superellipseCornerSDF(float2 point, float radius, float exponent) {
    point = abs(point);
    float value = pow(pow(point.x, exponent) + pow(point.y, exponent), 1.0f / exponent);
    return value - radius;
}

// Rounded rectangle SDF: Box with superellipse corners for customizable rounding.
// rect: float4(x, y, width, height) in points, upper-left origin
// fragmentCoord: pixel coordinates (upper-left origin)
float roundedRectangleSDF(float2 fragmentCoord, float4 rect, float cornerRadius, float roundnessExponent, constant ShaderUniforms& uniforms) {
    // Convert rectangle from points to pixels
    float2 rectOriginPx = rect.xy * uniforms.contentsScale;
    float2 rectSizePx = rect.zw * uniforms.contentsScale;
    float scaledCornerRadius = cornerRadius * uniforms.contentsScale;

    // Calculate rectangle center in pixels
    float2 rectCenterPx = rectOriginPx + rectSizePx * 0.5f;

    // Translate fragment to rectangle-centered coordinates
    float2 point = fragmentCoord - rectCenterPx;

    // Distance to unrounded box half-extents
    float2 halfExtents = rectSizePx * 0.5f;
    float2 edgeDistance = abs(point) - halfExtents;

    float surfaceDistance;

    if (edgeDistance.x > -scaledCornerRadius && edgeDistance.y > -scaledCornerRadius) {
        // Corner region: Apply superellipse rounding
        float2 cornerCenter = sign(point) * (halfExtents - float2(scaledCornerRadius));
        float2 cornerRelativePoint = point - cornerCenter;
        surfaceDistance = superellipseCornerSDF(cornerRelativePoint, scaledCornerRadius, roundnessExponent);
    } else {
        // Straight edges or interior: Standard rounded box formula
        surfaceDistance = min(max(edgeDistance.x, edgeDistance.y), 0.0f) + length(max(edgeDistance, 0.0f));
    }

    return surfaceDistance;
}

// Smooth union: Blends two SDFs with polynomial smoothing to avoid sharp seams during morphing.
float smoothUnion(float distanceA, float distanceB, float smoothness) {
    float hermite = clamp(0.5f + 0.5f * (distanceB - distanceA) / smoothness, 0.0f, 1.0f);
    return mix(distanceB, distanceA, hermite) - smoothness * hermite * (1.0f - hermite);
}

// Primary SDF: Merges all rectangles in the array using smooth union.
// fragmentCoord: pixel coordinates (upper-left origin)
float primaryShapeSDF(float2 fragmentCoord, constant ShaderUniforms& uniforms) {
    // Start with a large distance (outside all shapes)
    float combinedDistance = 1e10f;

    // Iterate over all active rectangles and compute smooth union
    for (int i = 0; i < uniforms.rectangleCount && i < maxRectangles; ++i) {
        float4 rect = uniforms.rectangles[i];

        // Skip empty rectangles
        if (rect.z <= 0.0f || rect.w <= 0.0f) continue;

        float rectDistance = roundedRectangleSDF(
            fragmentCoord,
            rect,
            uniforms.cornerRadius,
            uniforms.cornerRoundnessExponent,
            uniforms
        );

        // Normalize distance to resolution for consistent smooth union
        float normalizedRectDist = rectDistance / uniforms.resolution.y;

        if (i == 0) {
            combinedDistance = normalizedRectDist;
        } else {
            combinedDistance = smoothUnion(combinedDistance, normalizedRectDist, uniforms.shapeMergeSmoothness);
        }
    }

    return combinedDistance;
}

// =============================================================================
// Surface Normal Computation
// Gradients of SDF provide view-space normals for refraction and lighting.
// =============================================================================

// Adaptive finite-difference normal: Uses screen derivatives for epsilon (scale-aware).
// Raw gradient used (not normalized) in some steps for magnitude encoding.
float2 computeSurfaceNormal(float2 fragmentCoord, constant ShaderUniforms& uniforms) {
    // Adaptive epsilon from pixel derivatives (fallback to min for stability)
    float2 epsilon = float2(
        max(abs(dfdx(fragmentCoord.x)), 0.0001f),
        max(abs(dfdy(fragmentCoord.y)), 0.0001f)
    );

    float2 gradient = float2(
        primaryShapeSDF(fragmentCoord + float2(epsilon.x, 0.0f), uniforms) -
        primaryShapeSDF(fragmentCoord - float2(epsilon.x, 0.0f), uniforms),
        primaryShapeSDF(fragmentCoord + float2(0.0f, epsilon.y), uniforms) -
        primaryShapeSDF(fragmentCoord - float2(0.0f, epsilon.y), uniforms)
    ) / (2.0f * epsilon);

    // normalize(gradient);  // Commented: Raw gradient preferred for debug magnitude; normalized for effects
    return gradient * 1.414213562f * 1000.0f;  // Scaled for visualization
}

// Isotropic four-sample normal (diagonal finite differences for less bias).
float2 computeIsotropicNormal(float2 fragmentCoord, constant ShaderUniforms& uniforms) {
    float epsilon = 0.7071f * 0.0005f;  // Diagonal step size
    float2 offset1 = float2(1.0f, 1.0f);
    float2 offset2 = float2(-1.0f, 1.0f);
    float2 offset3 = float2(1.0f, -1.0f);
    float2 offset4 = float2(-1.0f, -1.0f);

    return normalize(
        offset1 * primaryShapeSDF(fragmentCoord + epsilon * offset1, uniforms) +
        offset2 * primaryShapeSDF(fragmentCoord + epsilon * offset2, uniforms) +
        offset3 * primaryShapeSDF(fragmentCoord + epsilon * offset3, uniforms) +
        offset4 * primaryShapeSDF(fragmentCoord + epsilon * offset4, uniforms)
    );
}

// Basic central-difference normal (simple axis-aligned).
float2 computeCentralNormal(float2 fragmentCoord, constant ShaderUniforms& uniforms) {
    float epsilon = 0.0005f;
    float2 offset = float2(epsilon, 0.0f);

    float dx = primaryShapeSDF(fragmentCoord + offset.xy, uniforms) -
               primaryShapeSDF(fragmentCoord - offset.xy, uniforms);
    float dy = primaryShapeSDF(fragmentCoord + offset.yx, uniforms) -
               primaryShapeSDF(fragmentCoord - offset.yx, uniforms);

    return normalize(float2(dx, dy));
}

// =============================================================================
// Color Space Utilities (Perceptual Adjustments via LCH)
// For tinting highlights without desaturation; based on CIE LAB/LCH conversions.
// Half for colors; float for matrices to preserve precision.
// =============================================================================

// D65 white point (sRGB standard)
constant float3 d65WhitePoint = float3(0.95045592705f, 1.0f, 1.08905775076f);
//constant float3 d50WhitePoint = float3(0.96429567643f, 1.0f, 0.82510460251f);
constant float3 whiteReference = d65WhitePoint;

// sRGB to XYZ matrix
constant float3x3 rgbToXyzMatrix = float3x3(
    float3(0.4124f, 0.3576f, 0.1805f),
    float3(0.2126f, 0.7152f, 0.0722f),
    float3(0.0193f, 0.1192f, 0.9505f)
);

// XYZ (D65) to XYZ (D50) adaptation
constant float3x3 xyzD65ToD50Matrix = float3x3(
    float3(1.0479298208405488f,  0.022946793341019088f, -0.05019222954313557f),
    float3(0.029627815688159344f,  0.990434484573249f  , -0.01707382502938514f),
    float3(-0.009243058152591178f,  0.015055144896577895f,  0.7518742899580008f)
);

// XYZ to linear RGB matrix
constant float3x3 xyzToRgbMatrix = float3x3(
    float3( 3.2406255f, -1.537208f , -0.4986286f),
    float3(-0.9689307f,  1.8757561f,  0.0415175f),
    float3( 0.0557101f, -0.2040211f,  1.0569959f)
);

// XYZ (D50) to XYZ (D65) adaptation
constant float3x3 xyzD50ToD65Matrix = float3x3(
    float3(0.9554734527042182f  , -0.023098536874261423f,  0.0632593086610217f  ),
    float3(-0.028369706963208136f,  1.0099954580058226f  ,  0.021041398966943008f),
    float3( 0.012314001688319899f, -0.020507696433477912f,  1.3303659366080753f )
);

// sRGB uncompanding (gamma to linear)
float linearizeSRGB(float channel) {
    return channel > 0.04045f ? pow((channel + 0.055f) / 1.055f, 2.4f) : channel / 12.92f;
}

// Linear to sRGB companding (apply gamma)
float gammaCorrectSRGB(float linear) {
    return linear <= 0.0031308f ? 12.92f * linear : 1.055f * pow(linear, 0.41666666666f) - 0.055f;
}

// Linear RGB to XYZ
float3 linearRgbToXyz(float3 linearRgb) {
    return (whiteReference.x == d65WhitePoint.x) ? linearRgb * rgbToXyzMatrix : linearRgb * rgbToXyzMatrix * xyzD65ToD50Matrix;
}

// sRGB to linear RGB
half3 srgbToLinear(half3 srgb) {
    return half3(linearizeSRGB(srgb.x), linearizeSRGB(srgb.y), linearizeSRGB(srgb.z));
}

// Linear RGB to sRGB
half3 linearToSrgb(half3 linear) {
    return half3(gammaCorrectSRGB(linear.x), gammaCorrectSRGB(linear.y), gammaCorrectSRGB(linear.z));
}

// sRGB to XYZ
float3 srgbToXyz(half3 srgb) {
    return linearRgbToXyz(float3(srgbToLinear(srgb)));
}

// XYZ to LAB non-linear transform
float xyzToLabNonlinear(float normalizedX) {
    // Threshold: (24/116)^3 ≈ 0.00885645167
    return normalizedX > 0.00885645167f ? pow(normalizedX, 1.0f / 3.0f) : 7.78703703704f * normalizedX + 0.13793103448f;
}

// XYZ to CIE LAB (perceptual uniform space)
float3 xyzToLab(float3 xyz) {
    float3 scaledXyz = xyz / whiteReference;
    scaledXyz = float3(
        xyzToLabNonlinear(scaledXyz.x),
        xyzToLabNonlinear(scaledXyz.y),
        xyzToLabNonlinear(scaledXyz.z)
    );
    return float3(
        116.0f * scaledXyz.y - 16.0f,  // Lightness (L)
        500.0f * (scaledXyz.x - scaledXyz.y),  // a* (green-red)
        200.0f * (scaledXyz.y - scaledXyz.z)   // b* (blue-yellow)
    );
}

// sRGB to LAB
float3 srgbToLab(half3 srgb) {
    return xyzToLab(srgbToXyz(srgb));
}

// LAB to LCH (cylindrical: Lightness, Chroma, Hue in degrees)
float3 labToLch(float3 lab) {
    float chroma = sqrt(dot(lab.yz, lab.yz));
    float hueDegrees = atan2(lab.z, lab.y) * (180.0f / PI);
    return float3(lab.x, chroma, hueDegrees);
}

// sRGB to LCH
float3 srgbToLch(half3 srgb) {
    return labToLch(srgbToLab(srgb));
}

// XYZ to linear RGB
float3 xyzToLinearRgb(float3 xyz) {
    return (whiteReference.x == d65WhitePoint.x) ? xyz * xyzToRgbMatrix : xyz * xyzD50ToD65Matrix * xyzToRgbMatrix;
}

// XYZ to sRGB
half3 xyzToSrgb(float3 xyz) {
    return linearToSrgb(half3(xyzToLinearRgb(xyz)));
}

// LAB to XYZ inverse non-linear
float labToXyzNonlinear(float transformed) {
    // Threshold: 6/29 ≈ 0.206897
    return transformed > 0.206897f ? transformed * transformed * transformed : 0.12841854934f * (transformed - 0.137931034f);
}

// LAB to XYZ
float3 labToXyz(float3 lab) {
    float whiteScaled = (lab.x + 16.0f) / 116.0f;
    return whiteReference * float3(
        labToXyzNonlinear(whiteScaled + lab.y / 500.0f),
        labToXyzNonlinear(whiteScaled),
        labToXyzNonlinear(whiteScaled - lab.z / 200.0f)
    );
}

// LAB to sRGB
half3 labToSrgb(float3 lab) {
    return xyzToSrgb(labToXyz(lab));
}

// LCH to LAB
float3 lchToLab(float3 lch) {
    float hueRadians = lch.z * (PI / 180.0f);
    return float3(lch.x, lch.y * cos(hueRadians), lch.y * sin(hueRadians));
}

// LCH to sRGB
half3 lchToSrgb(float3 lch) {
    return labToSrgb(lchToLab(lch));
}

// HSV to RGB (for normal rainbow visualization)
half3 hsvToRgb(half3 hsv) {
    half4 k = half4(1.0h, 2.0h / 3.0h, 1.0h / 3.0h, 3.0h);
    half3 p = abs(fract(hsv.xxx + k.xyz) * 6.0h - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, 0.0h, 1.0h), hsv.y);
}

// Vector to angle [0, 2π]
float vectorToAngle(float2 vector) {
    float angle = atan2(vector.y, vector.x);
    return (angle < 0.0f) ? angle + 2.0f * PI : angle;
}

// Normalized vector to rainbow color (HSV hue from angle)
half3 vectorToRainbowColor(float2 vector) {
    float angle = vectorToAngle(vector);
    half hue = half(angle / (2.0f * PI));
    half3 hsv = half3(hue, 1.0h, 1.0h);
    return hsvToRgb(hsv);
}

// Texture sample with per-channel dispersion offset (simulates prism fringing).
// Samples R/G/B separately with refractive index-based UV shifts.
half4 sampleWithDispersion(texture2d<half> texture, float2 baseUv, float2 offset, float dispersionFactor) {
    half4 color = half4(1.0h);
    // Red: Minimal shift (lower index)
    color.r = texture.sample(textureSampler, baseUv + offset * (1.0f - (refractiveIndexRed - 1.0f) * dispersionFactor)).r;
    // Green: Neutral
    color.g = texture.sample(textureSampler, baseUv + offset * (1.0f - (refractiveIndexGreen - 1.0f) * dispersionFactor)).g;
    // Blue: Maximal shift (higher index)
    color.b = texture.sample(textureSampler, baseUv + offset * (1.0f - (refractiveIndexBlue - 1.0f) * dispersionFactor)).b;
    return color;
}

// =============================================================================
// Fragment Shader: Full Progressive Effect Pipeline
// =============================================================================
fragment half4 liquidGlassEffect(VertexOutput input [[stage_in]],
                                 constant ShaderUniforms& uniforms [[buffer(0)]],
                                 texture2d<half> background [[texture(0)]]) {

    // Logical resolution (scale-normalized)
    float2 logicalResolution = uniforms.resolution / uniforms.contentsScale;

    // Fragment coordinate in pixels (from UV, upper-left origin)
    float2 fragmentPixelCoord = float2(input.uv) * uniforms.resolution;

    // Primary merged SDF distance (normalized to resolution.y)
    float shapeDistance = primaryShapeSDF(fragmentPixelCoord, uniforms);

    half4 outputColor;

    // Pixel size for anti-aliasing (y-dominant for aspect)
//    float pixelSize = 2.0f / uniforms.resolution.y;

    // Slightly expanded threshold for smoother AA
    if (shapeDistance < 0.005f) {
        float normalizedDepth = -shapeDistance * logicalResolution.y;

        // Refraction shift factor
        float depthRatio = 1.0f - normalizedDepth / uniforms.glassThickness;
        float incidentAngle = asin(pow(depthRatio, 2.0f));
        float transmittedAngle = asin(1.0f / uniforms.refractiveIndex * sin(incidentAngle));
        float edgeShiftFactor = -tan(transmittedAngle - incidentAngle);
        if (normalizedDepth >= uniforms.glassThickness) {
            edgeShiftFactor = 0.0f;
        }

        if (edgeShiftFactor <= 0.0f) {
            outputColor = background.sample(textureSampler, float2(input.uv));
            outputColor = mix(outputColor, half4(half3(uniforms.materialTint.rgb), 1.0h), half(uniforms.materialTint.a * 0.8f));
        } else {
            float2 surfaceNormal = computeSurfaceNormal(fragmentPixelCoord, uniforms);
            // Dispersion-sampled refraction (scale/aspect corrected)
            half2 offsetUv = half2(-surfaceNormal * edgeShiftFactor * 0.05f * uniforms.contentsScale * float2(
                uniforms.resolution.y / (logicalResolution.x * uniforms.contentsScale),
                1.0f
            ));
            half4 refractedWithDispersion = sampleWithDispersion(background, float2(input.uv), float2(offsetUv), uniforms.dispersionStrength);

            // Base material tint
            outputColor = mix(refractedWithDispersion, half4(half3(uniforms.materialTint.rgb), 1.0h), half(uniforms.materialTint.a * 0.8f));

            // Fresnel: LCH-lightness boosted reflection
            float fresnelValue = clamp(
                pow(
                    1.0f + shapeDistance * logicalResolution.y / 1500.0f * pow(500.0f / uniforms.fresnelDistanceRange, 2.0f) + uniforms.fresnelEdgeSharpness,
                    5.0f
                ),
                0.0f, 1.0f
            );

            half3 fresnelBaseTint = mix(half3(1.0h), half3(uniforms.materialTint.rgb), half(uniforms.materialTint.a * 0.5f));
            float3 fresnelLch = srgbToLch(fresnelBaseTint);
            fresnelLch.x += 20.0f * fresnelValue * uniforms.fresnelIntensity;
            fresnelLch.x = clamp(fresnelLch.x, 0.0f, 100.0f);

            outputColor = mix(
                outputColor,
                half4(lchToSrgb(fresnelLch), 1.0h),
                half(fresnelValue * uniforms.fresnelIntensity * 0.7f * length(surfaceNormal))
            );

            // Glare: Directional, LCH-boosted (lightness + chroma)
            float glareGeometryValue = clamp(
                pow(
                    1.0f + shapeDistance * logicalResolution.y / 1500.0f * pow(500.0f / uniforms.glareDistanceRange, 2.0f) + uniforms.glareEdgeSharpness,
                    5.0f
                ),
                0.0f, 1.0f
            );

            float glareAngle = (vectorToAngle(normalize(surfaceNormal)) - PI / 4.0f + uniforms.glareDirectionOffset) * 2.0f;
            int isFarSide = 0;
            if ((glareAngle > PI * (2.0f - 0.5f) && glareAngle < PI * (4.0f - 0.5f)) || glareAngle < PI * (0.0f - 0.5f)) {
                isFarSide = 1;
            }
            float angularGlare = (0.5f + sin(glareAngle) * 0.5f) *
                                 (isFarSide == 1 ? 1.2f * uniforms.glareOppositeSideBias : 1.2f) *
                                 uniforms.glareIntensity;
            angularGlare = clamp(pow(angularGlare, 0.1f + uniforms.glareAngleConvergence * 2.0f), 0.0f, 1.0f);

            half3 baseGlare = mix(refractedWithDispersion.rgb, half3(uniforms.materialTint.rgb), half(uniforms.materialTint.a * 0.5f));
            float3 glareLch = srgbToLch(baseGlare);
            glareLch.x += 150.0f * angularGlare * glareGeometryValue;
            glareLch.y += 30.0f * angularGlare * glareGeometryValue;
            glareLch.x = clamp(glareLch.x, 0.0f, 120.0f);

            outputColor = mix(
                outputColor,
                half4(lchToSrgb(glareLch), 1.0h),
                half(angularGlare * glareGeometryValue * length(surfaceNormal))
            );
        }
    } else {
        outputColor = half4(0);//background.sample(textureSampler, float2(input.uv));
    }

    // Boundary anti-aliasing (smoothstep blend)
    outputColor = mix(outputColor, half4(0), smoothstep(-0.01f, 0.005f, shapeDistance));

    return outputColor;
}
