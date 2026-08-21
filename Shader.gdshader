shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// --- ADMECH THEME CONTROLS ---
uniform float scanline_density : hint_range(100.0, 1000.0) = 480.0;
uniform float scanline_intensity : hint_range(0.0, 0.5) = 0.08;
uniform float aberration_amount : hint_range(0.0, 0.02) = 0.003;
uniform float vignette_intensity : hint_range(0.0, 1.5) = 0.55;
uniform float phosphor_decay : hint_range(0.0, 0.2) = 0.02;

// Pseudo-random noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // 1. Lens Distortion / Edge Chromatic Aberration (Bionic Lens Optic)
    vec2 center_offset = uv - vec2(0.5);
    float dist = dot(center_offset, center_offset);
    vec2 aberration = center_offset * dist * aberration_amount;
    
    float r = texture(SCREEN_TEXTURE, uv + aberration).r;
    float g = texture(SCREEN_TEXTURE, uv).g;
    float b = texture(SCREEN_TEXTURE, uv - aberration).b;
    vec3 col = vec3(r, g, b);
    
    // 2. Imperial Cogitator Scanlines
    float scanline = sin(uv.y * scanline_density * 3.14159) * 0.5 + 0.5;
    col -= col * (scanline * scanline_intensity);
    
    // 3. Static Grain / Radioactive Fallout Interference
    float noise = (hash(uv + vec2(TIME * 0.08, 0.0)) - 0.5) * phosphor_decay;
    col += noise;
    
    // 4. Color Grading: Forge-World Martian Spectrum
    // Boosts warm brass/amber midtones, preserves cyan plasma highlights
    col.r = mix(col.r, col.r * 1.06, 0.5);
    col.b = mix(col.b, col.b * 0.95 + col.g * 0.05, 0.3);
    
    // 5. Heavy Tactical Auspex Vignette
    col *= clamp(1.0 - dist * vignette_intensity, 0.0, 1.0);
    
    COLOR = vec4(col, 1.0);
}