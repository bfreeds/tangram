uniform vec2 u_resolution;
uniform float u_time;
uniform vec3 u_map_position;
uniform vec4 u_tile_origin;
uniform float u_meters_per_pixel;
uniform float u_device_pixel_ratio;

uniform mat3 u_normalMatrix;
uniform mat3 u_inverseNormalMatrix;

varying vec4 v_position;
varying vec3 v_normal;
varying vec4 v_color;
varying vec4 v_world_position;

#ifdef TANGRAM_EXTRUDE_LINES
    uniform bool u_has_line_texture;
    uniform sampler2D u_texture;
    uniform float u_texture_ratio;
    uniform vec4 u_dash_background_color;
#endif

#define TANGRAM_NORMAL v_normal

#if defined(TANGRAM_TEXTURE_COORDS) || defined(TANGRAM_EXTRUDE_LINES)
    varying vec2 v_texcoord;
#endif

#ifdef TANGRAM_MODEL_POSITION_BASE_ZOOM_VARYING
    varying vec4 v_modelpos_base_zoom;
#endif

#if defined(TANGRAM_LIGHTING_VERTEX)
    varying vec4 v_lighting;
#endif

#pragma tangram: camera
#pragma tangram: material
#pragma tangram: lighting
#pragma tangram: raster
#pragma tangram: global

void main (void) {
    // Initialize globals
    #pragma tangram: setup

    vec4 color = v_color;
    vec3 normal = TANGRAM_NORMAL;

    // Apply raster to vertex color
    #ifdef TANGRAM_RASTER_TEXTURE_COLOR
    { // enclose in scope to avoid leakage of internal variables
        vec4 raster_color = sampleRaster(0);

        #ifdef TANGRAM_BLEND_OPAQUE
            // Raster sources can optionally mask by the alpha channel, which will render with only full or no alpha.
            // This is used for handling transparency outside the raster image when rendering with opaque blending,
            // which doesn't support alpha (with expected results anyway).
            #ifdef TANGRAM_HAS_MASKED_RASTERS   // skip masking logic if no masked raster sources
            #ifndef TANGRAM_ALL_MASKED_RASTERS  // skip conditional if *only* masked raster sources (always true)
            if (u_raster_mask_alpha) {
            #else
            {
            #endif
                if (raster_color.a < 1. - TANGRAM_EPSILON) {
                    discard;
                }
                // only allow full alpha in opaque blend mode (avoids artifacts blending w/canvas tile background)
                raster_color.a = 1.;
            }
            #endif
        #endif

        color *= raster_color; // multiplied to tint texture color
    }
    #endif

    // Apply line texture
    #ifdef TANGRAM_EXTRUDE_LINES
    { // enclose in scope to avoid leakage of internal variables
        if (u_has_line_texture) {
            vec2 _line_st = vec2(v_texcoord.x, fract(v_texcoord.y / u_texture_ratio));
            vec4 _line_color = texture2D(u_texture, _line_st);

            if (_line_color.a < TANGRAM_ALPHA_TEST) {
                #if defined(TANGRAM_BLEND_OPAQUE)
                    // use discard when alpha blending is unavailable
                    if (u_dash_background_color.a < 1. - TANGRAM_EPSILON) {
                        discard;
                    }
                    color = vec4(u_dash_background_color.rgb, 1.); // only allow full alpha in opaque blend mode
                #else
                    // use alpha channel when blending is available
                    color = vec4(u_dash_background_color.rgb, color.a * step(TANGRAM_EPSILON, u_dash_background_color.a));
                #endif
            }
            else {
                color *= _line_color;
            }
        }
    }
    #endif

    // First, get normal from raster tile (if applicable)
    #ifdef TANGRAM_RASTER_TEXTURE_NORMAL
        normal = normalize(sampleRaster(0).rgb * 2. - 1.);
    #endif

    // Second, alter normal with normal map texture (if applicable)
    #if defined(TANGRAM_LIGHTING_FRAGMENT) && defined(TANGRAM_MATERIAL_NORMAL_TEXTURE)
        calculateNormal(normal);
    #endif

    // Normal modification applied here for fragment lighting or no lighting,
    // and in vertex shader for vertex lighting
    #if !defined(TANGRAM_LIGHTING_VERTEX)
        #pragma tangram: normal
    #endif

    // Color modification before lighting is applied
    #pragma tangram: color

    #if defined(TANGRAM_LIGHTING_FRAGMENT)
        // Calculate per-fragment lighting
        color = calculateLighting(v_position.xyz - u_eye, normal, color);
    #elif defined(TANGRAM_LIGHTING_VERTEX)
        // Apply lighting intensity interpolated from vertex shader
        color *= v_lighting;
    #endif

    // Post-processing effects (modify color after lighting)
    #pragma tangram: filter

    gl_FragColor = color;
}
