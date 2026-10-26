# SCons options for the custom web engine (scripts/build.py --web-engine):
# the stock 4.7.2 dlink/nothreads template without the modules and servers the
# game never uses, so phones download and compile far less wasm. Everything
# the game loads is imported into the pack (.ctex, .scn, .oggvorbisstr), so
# the import-only modules (image formats, glTF, FBX, compressors) can go.
# Kept on purpose: svg (the default theme's icons are SVG), webp (lossless
# .ctex), freetype + text_server_fb (fonts; Latin and Cyrillic need no
# shaping), ogg/vorbis (the instructor's voice), regex, jolt_physics, mbedtls,
# vhacd (the car's collision hull is simplified with it, car.gd).

# platform, target, threads, dlink_enabled, optimize and lto are given on
# build.py's command line: SCons reads them before this file.

# deprecated stays on: godot-cpp calls get_godot_version and the scripts
# Image.create(), both behind it.
brotli = False
disable_physics_2d = True
disable_navigation_2d = True
disable_navigation_3d = True
disable_xr = True

module_astcenc_enabled = False
module_basis_universal_enabled = False
module_bcdec_enabled = False
module_betsy_enabled = False
module_bmp_enabled = False
module_camera_enabled = False
module_csg_enabled = False
module_cvtt_enabled = False
module_dds_enabled = False
module_enet_enabled = False
module_etcpak_enabled = False
module_fbx_enabled = False
module_glslang_enabled = False
module_gltf_enabled = False
module_gridmap_enabled = False
module_godot_physics_2d_enabled = False
module_godot_physics_3d_enabled = False
module_hdr_enabled = False
module_interactive_music_enabled = False
module_jpg_enabled = False
module_jsonrpc_enabled = False
module_ktx_enabled = False
module_lightmapper_rd_enabled = False
module_meshoptimizer_enabled = False
module_mobile_vr_enabled = False
module_mono_enabled = False
module_mp3_enabled = False
module_msdfgen_enabled = False
module_multiplayer_enabled = False
module_navigation_2d_enabled = False
module_navigation_3d_enabled = False
module_noise_enabled = False
module_objectdb_profiler_enabled = False
module_openxr_enabled = False
module_raycast_enabled = False
module_text_server_adv_enabled = False
module_text_server_fb_enabled = True
module_tga_enabled = False
module_theora_enabled = False
module_tinyexr_enabled = False
module_upnp_enabled = False

module_visual_shader_enabled = False
module_webrtc_enabled = False
module_websocket_enabled = False
module_webxr_enabled = False
module_xatlas_unwrap_enabled = False
module_zip_enabled = False
