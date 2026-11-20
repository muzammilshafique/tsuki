// Fragment shader for 0-FBO GPU rounded-corner cover images with PreserveAspectCrop
// and optional top/bottom vignettes + darkening overlay.
//
// Regenerate compiled QSB bytecode with:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o resources/shaders/rounded_cover.frag.qsb resources/shaders/rounded_cover.frag

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 texSize;
    float topRadius;
    float bottomRadius;
    float topVignetteAlpha;
    float topVignetteHeight;
    float bottomVignetteAlpha;
    float bottomVignetteHeight;
    float darkenAlpha;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 size = max(itemSize, vec2(1.0));
    vec2 halfSize = 0.5 * size;
    vec2 px = qt_TexCoord0 * size;
    vec2 p = px - halfSize;

    float r = (p.y < 0.0) ? topRadius : bottomRadius;
    r = clamp(r, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + vec2(r);
    float dist = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    float aa = max(fwidth(dist), 0.75);
    float maskAlpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, dist);

    // PreserveAspectCrop UV mapping matching Qt Quick Image
    float itemAspect = size.x / size.y;
    float texAspect = max(texSize.x, 1.0) / max(texSize.y, 1.0);
    vec2 uv = qt_TexCoord0;
    if (texAspect > itemAspect) {
        float scale = itemAspect / texAspect;
        uv.x = (uv.x - 0.5) * scale + 0.5;
    } else {
        float scale = texAspect / itemAspect;
        uv.y = (uv.y - 0.5) * scale + 0.5;
    }

    vec4 col = texture(source, uv);

    // Composite black vignettes & hover darkening over premultiplied source color
    float shade = clamp(darkenAlpha, 0.0, 1.0);
    if (topVignetteAlpha > 0.001 && topVignetteHeight > 0.5) {
        float t = clamp(1.0 - px.y / topVignetteHeight, 0.0, 1.0);
        shade = 1.0 - (1.0 - shade) * (1.0 - t * topVignetteAlpha);
    }
    if (bottomVignetteAlpha > 0.001 && bottomVignetteHeight > 0.5) {
        float b = clamp(1.0 - (size.y - px.y) / bottomVignetteHeight, 0.0, 1.0);
        shade = 1.0 - (1.0 - shade) * (1.0 - b * bottomVignetteAlpha);
    }

    col.rgb = col.rgb * (1.0 - shade);
    col.a = shade + col.a * (1.0 - shade);
    fragColor = col * (maskAlpha * qt_Opacity);
}

