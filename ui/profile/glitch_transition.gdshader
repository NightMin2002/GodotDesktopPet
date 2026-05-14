shader_type canvas_item;

uniform float glitch_power : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// 伪随机数生成
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
    if (glitch_power <= 0.001) {
        COLOR = texture(screen_texture, SCREEN_UV);
    } else {
        // 降低为低频跳动，保护光敏癫痫患者（PSE安全）
        // 限制大幅乱闪，采用平滑且具有模拟磁带（VHS）质感的沉稳撕裂
        
        float time_step = floor(TIME * 12.0); // 降帧处理扰动频率，避免60Hz高频闪烁
        
        // 切片高度不再是疯狂跳动，而是稳定的大区段撕裂
        float slice_h = 0.03 + sin(TIME * 2.0) * 0.015;
        float slice_v = floor(SCREEN_UV.y / slice_h);
        
        // 平滑的偏移动力学，加入正弦波让其有连续的扭曲感
        float base_shift = sin(slice_v * 10.0 + TIME * 3.0) * glitch_power * 0.1;
        float rnd = random(vec2(slice_v, time_step));
        float spike_shift = (rnd - 0.5) * glitch_power * 0.15;
        
        float shift = base_shift + spike_shift;
        
        // 色差保持安全范围内（不刺眼，电影级色差）
        float ca_shift = glitch_power * 0.02;

        vec2 uv_r = SCREEN_UV + vec2(shift + ca_shift, 0.0);
        vec2 uv_g = SCREEN_UV + vec2(shift, 0.0);
        vec2 uv_b = SCREEN_UV + vec2(shift - ca_shift, 0.0);
        
        // 温和的垂直拉伸代替波浪扭曲
        float v_stretch = (random(vec2(time_step, 0.0)) - 0.5) * glitch_power * 0.02;
        uv_r.y += v_stretch; uv_g.y += v_stretch; uv_b.y += v_stretch;

        float r = texture(screen_texture, uv_r).r;
        float g = texture(screen_texture, uv_g).g;
        float b = texture(screen_texture, uv_b).b;
        
        // CRT 扫描线压暗效果（取代原来刺眼的白色高光和变色白块噪点）
        float scanline = sin(SCREEN_UV.y * 800.0) * 0.04 * glitch_power;
        r -= scanline; g -= scanline; b -= scanline;
        
        // 轻微的信号衰减降饱和，而非高亮
        if (glitch_power > 0.1) {
            float avg = (r + g + b) / 3.0;
            // 温和地向系统绿靠拢，绝不高对比频闪
            float blend = glitch_power * 0.5;
            r = mix(r, avg * 0.8, blend);
            g = mix(g, avg * 1.2, blend);
            b = mix(b, avg * 0.8, blend);
        }
        
        COLOR = vec4(r, g, b, 1.0);
    }
}
