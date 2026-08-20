set(XXSNAP_WINDOWS_FAMILY "modern" CACHE STRING "Windows target family (modern or legacy)")
set_property(CACHE XXSNAP_WINDOWS_FAMILY PROPERTY STRINGS modern legacy)

if(MSVC)
    add_compile_options($<$<COMPILE_LANGUAGE:CXX>:/utf-8>)
endif()

set(XXSNAP_VERSION "0.1.0" CACHE STRING "XxSnap executable version (major.minor.patch)")
string(REGEX MATCH "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$" XXSNAP_VERSION_MATCH "${XXSNAP_VERSION}")
if(NOT XXSNAP_VERSION_MATCH)
    message(FATAL_ERROR
        "Invalid XXSNAP_VERSION='${XXSNAP_VERSION}'; expected major.minor.patch"
    )
endif()
set(XXSNAP_VERSION_MAJOR "${CMAKE_MATCH_1}")
set(XXSNAP_VERSION_MINOR "${CMAKE_MATCH_2}")
set(XXSNAP_VERSION_PATCH "${CMAKE_MATCH_3}")
foreach(VERSION_PART IN ITEMS
        XXSNAP_VERSION_MAJOR XXSNAP_VERSION_MINOR XXSNAP_VERSION_PATCH)
    if(${VERSION_PART} GREATER 65535)
        message(FATAL_ERROR "${VERSION_PART} must be <= 65535 for VERSIONINFO")
    endif()
endforeach()

if(NOT XXSNAP_WINDOWS_FAMILY STREQUAL "modern" AND
   NOT XXSNAP_WINDOWS_FAMILY STREQUAL "legacy")
    message(FATAL_ERROR
        "Invalid XXSNAP_WINDOWS_FAMILY='${XXSNAP_WINDOWS_FAMILY}'; expected modern or legacy"
    )
endif()

add_library(xxsnap_windows_build_configuration INTERFACE)

enable_language(RC)
set(XXSNAP_VERSION_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/xxsnap_version.rc")
configure_file(
    resources/xxsnap_version.rc.in
    "${XXSNAP_VERSION_RESOURCE}"
    @ONLY
)
add_library(
    xxsnap_visual_assets OBJECT
    resources/xxsnap.rc
    "${XXSNAP_VERSION_RESOURCE}"
)
target_include_directories(
    xxsnap_visual_assets
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
        "${PROJECT_SOURCE_DIR}"
)
file(GLOB_RECURSE XXSNAP_TOOLBAR_ASSET_FILES
    CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/resources/toolbar/*/*.png"
)
set_property(
    SOURCE resources/xxsnap.rc
    APPEND PROPERTY OBJECT_DEPENDS
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/Snipory.ico"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/cursors/xxsnap-crosshair.cur"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/cursors/xxsnap-rotation.cur"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/cursors/xxsnap-eyedropper.cur"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/cursors/xxsnap-eyedropper-light.cur"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/cursors/xxsnap-eraser.cur"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/palette-tool.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/text-bold.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/text-bold-selected.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/text-italic.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/text-italic-selected.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/text-stroke.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/text-stroke-selected.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/ocr-correct.bmp"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/ocr-failed.bmp"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/correct.svg"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/failed.svg"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/sounds/fullscreencutsound.wav"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/sounds/notification.wav"
        ${XXSNAP_TOOLBAR_ASSET_FILES}
)
add_library(xxsnap_visual_resources INTERFACE)
target_sources(
    xxsnap_visual_resources
    INTERFACE $<TARGET_OBJECTS:xxsnap_visual_assets>
)

if(XXSNAP_WINDOWS_FAMILY STREQUAL "modern")
    target_compile_definitions(xxsnap_windows_build_configuration INTERFACE
        XXSNAP_MODERN
        _WIN32_WINNT=0x0A00
        WINVER=0x0A00
    )
else()
    if(DEFINED MSVC_TOOLSET_VERSION AND
       NOT MSVC_TOOLSET_VERSION STREQUAL "" AND
       NOT MSVC_TOOLSET_VERSION STREQUAL "142")
        message(FATAL_ERROR
            "Legacy Windows builds require MSVC toolset v142; detected v${MSVC_TOOLSET_VERSION}"
        )
    endif()
    target_compile_definitions(xxsnap_windows_build_configuration INTERFACE
        XXSNAP_LEGACY
        _WIN32_WINNT=0x0601
        WINVER=0x0601
    )
endif()

add_executable(xxsnap_toolchain_probe src/build/ToolchainProbe.cpp)
target_compile_features(xxsnap_toolchain_probe PRIVATE cxx_std_20)
target_link_libraries(xxsnap_toolchain_probe PRIVATE xxsnap_windows_build_configuration)

add_library(
    xxsnap_capture_session_state
    src/session/CaptureSessionStateMachine.cpp
)
target_compile_features(xxsnap_capture_session_state PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_capture_session_state
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

add_library(
    xxsnap_selection_model
    src/overlay/SelectionModel.cpp
)
target_compile_features(xxsnap_selection_model PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_selection_model
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(xxsnap_selection_model PUBLIC snipory_core_portable)

add_library(
    xxsnap_display_topology
    src/capture/DisplayTopology.cpp
    src/support/RuntimeApis.cpp
)
target_compile_features(xxsnap_display_topology PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_display_topology
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_display_topology
    PUBLIC snipory_core_portable
    PRIVATE xxsnap_windows_build_configuration user32 gdi32
)

add_library(xxsnap_capture_backend INTERFACE)
target_compile_features(xxsnap_capture_backend INTERFACE cxx_std_17)
target_include_directories(
    xxsnap_capture_backend
    INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_capture_backend
    INTERFACE xxsnap_display_topology snipory_core_portable
)

add_library(
    xxsnap_gdi_capture_backend
    src/capture/GdiCaptureBackend.cpp
)
target_compile_features(xxsnap_gdi_capture_backend PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_gdi_capture_backend
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_gdi_capture_backend
    PUBLIC xxsnap_capture_backend
    PRIVATE xxsnap_display_topology snipory_core_portable
            xxsnap_windows_build_configuration user32 gdi32
)

add_library(
    xxsnap_dxgi_capture_backend
    src/capture/DxgiCaptureBackend.cpp
)
target_compile_features(xxsnap_dxgi_capture_backend PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_dxgi_capture_backend
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_dxgi_capture_backend
    PUBLIC xxsnap_capture_backend
    PRIVATE xxsnap_windows_build_configuration d3d11 dxgi
)

add_library(
    xxsnap_fallback_capture_backend
    src/capture/FallbackCaptureBackend.cpp
)
target_compile_features(xxsnap_fallback_capture_backend PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_fallback_capture_backend
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_fallback_capture_backend
    PUBLIC xxsnap_capture_backend
    PRIVATE xxsnap_dxgi_capture_backend xxsnap_gdi_capture_backend
            xxsnap_windows_build_configuration
)

add_library(
    xxsnap_selection_composer
    src/export/SelectionComposer.cpp
)
target_compile_features(xxsnap_selection_composer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_selection_composer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_selection_composer
    PUBLIC xxsnap_capture_backend
)

add_library(
    xxsnap_scroll_capture_session
    src/scroll/ScrollCaptureSession.cpp
)
target_compile_features(xxsnap_scroll_capture_session PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_scroll_capture_session
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_scroll_capture_session
    PUBLIC snipory_core_scroll snipory_core_portable
)

add_library(
    xxsnap_scroll_capture_target_detector
    src/scroll/ScrollCaptureTargetDetector.cpp
)
target_compile_features(
    xxsnap_scroll_capture_target_detector PUBLIC cxx_std_17
)
target_include_directories(
    xxsnap_scroll_capture_target_detector
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_scroll_capture_target_detector
    PUBLIC snipory_core_portable
    PRIVATE ole32
)

add_library(
    xxsnap_scroll_region_capturer
    src/scroll/ScrollRegionCapturer.cpp
)
target_compile_features(xxsnap_scroll_region_capturer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_scroll_region_capturer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_scroll_region_capturer
    PUBLIC xxsnap_gdi_capture_backend snipory_core_scroll
)

add_library(
    xxsnap_scroll_capture_host
    src/scroll/ScrollCaptureHost.cpp
)

target_compile_features(xxsnap_scroll_capture_host PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_scroll_capture_host
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_scroll_capture_host
    PUBLIC xxsnap_scroll_capture_session
           xxsnap_scroll_capture_target_detector
           xxsnap_scroll_region_capturer
           xxsnap_toolbar_layout
    PRIVATE xxsnap_annotation_composer xxsnap_display_topology
            xxsnap_overlay_host
            gdi32 user32 ole32 windowscodecs msimg32
)

add_library(
    xxsnap_annotation_composer
    src/export/AnnotationComposer.cpp
)
target_compile_features(xxsnap_annotation_composer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_annotation_composer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_annotation_composer
    PUBLIC xxsnap_annotation_renderer xxsnap_capture_backend
    PRIVATE xxsnap_windows_build_configuration d2d1 windowscodecs ole32
)

add_library(
    xxsnap_png_writer
    src/export/PngWriter.cpp
)
target_compile_features(xxsnap_png_writer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_png_writer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_png_writer
    PUBLIC snipory_core_portable
    PRIVATE xxsnap_windows_build_configuration windowscodecs ole32
)

add_library(
    xxsnap_clipboard_writer
    src/export/ClipboardWriter.cpp
)
target_compile_features(xxsnap_clipboard_writer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_clipboard_writer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_clipboard_writer
    PUBLIC xxsnap_png_writer snipory_core_portable
    PRIVATE xxsnap_windows_build_configuration user32
)

add_library(
    xxsnap_pinned_image_host
    src/pin/PinnedImageGeometry.cpp
    src/pin/PinnedImageHost.cpp
    src/pin/PinnedImageShadow.cpp
)
target_compile_features(xxsnap_pinned_image_host PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_pinned_image_host
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_pinned_image_host
    PUBLIC xxsnap_clipboard_writer xxsnap_png_writer snipory_core_portable
    PRIVATE xxsnap_preferences_settings xxsnap_windows_build_configuration
            user32 gdi32 comdlg32
)

add_library(
    xxsnap_toolbar_layout
    src/toolbar/ToolbarLayout.cpp
)
target_compile_features(xxsnap_toolbar_layout PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_toolbar_layout
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

add_library(
    xxsnap_toolbar_state
    src/toolbar/ToolbarState.cpp
)
target_compile_features(xxsnap_toolbar_state PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_toolbar_state
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

add_library(
    xxsnap_annotation_document
    src/annotation/AnnotationDocument.cpp
)
target_compile_features(xxsnap_annotation_document PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_annotation_document
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

add_library(
    xxsnap_shape_interaction
    src/annotation/ShapeInteraction.cpp
)
target_compile_features(xxsnap_shape_interaction PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_shape_interaction
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
add_library(
    xxsnap_text_annotation_renderer
    src/annotation/TextAnnotationRenderer.cpp
)
target_compile_features(xxsnap_text_annotation_renderer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_text_annotation_renderer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_text_annotation_renderer
    PUBLIC xxsnap_annotation_document
    PRIVATE d2d1 dwrite
)

target_link_libraries(
    xxsnap_shape_interaction
    PUBLIC xxsnap_annotation_document xxsnap_text_annotation_renderer
)

add_library(
    xxsnap_shape_options
    src/annotation/ShapeOptions.cpp
)
target_compile_features(xxsnap_shape_options PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_shape_options
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

add_library(
    xxsnap_annotation_renderer
    src/annotation/AnnotationRenderer.cpp
    src/annotation/ArrowLineRenderer.cpp
    src/annotation/BrushRenderer.cpp
    src/annotation/MarkerRenderer.cpp
    src/annotation/NumberAnnotationRenderer.cpp
)
target_compile_features(xxsnap_annotation_renderer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_annotation_renderer
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_annotation_renderer
    PUBLIC xxsnap_annotation_document xxsnap_text_annotation_renderer
    PRIVATE d2d1 dwrite
)

add_library(
    xxsnap_shape_editor_controller
    src/annotation/ArrowLineInteraction.cpp
    src/annotation/BrushInteraction.cpp
    src/annotation/MarkerInteraction.cpp
    src/annotation/MosaicInteraction.cpp
    src/annotation/ShapeEditorController.cpp
)
target_compile_features(xxsnap_shape_editor_controller PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_shape_editor_controller
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_shape_editor_controller
    PUBLIC xxsnap_annotation_document xxsnap_annotation_renderer
           xxsnap_shape_interaction xxsnap_shape_options xxsnap_toolbar_state
)

add_library(
    xxsnap_overlay_renderer
    src/overlay/Eyedropper.cpp
    src/overlay/OverlayRenderer.cpp
)
target_compile_features(xxsnap_overlay_renderer PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_overlay_renderer
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)
target_link_libraries(
    xxsnap_overlay_renderer
    PUBLIC xxsnap_capture_backend xxsnap_visual_resources xxsnap_toolbar_layout
           xxsnap_annotation_renderer xxsnap_shape_options
    PRIVATE xxsnap_windows_build_configuration
            d2d1 dwrite windowscodecs ole32 user32 gdi32
)

add_library(
    xxsnap_overlay_window
    src/overlay/OverlayWindow.cpp
)
target_compile_features(xxsnap_overlay_window PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_overlay_window
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)
target_link_libraries(
    xxsnap_overlay_window
    PUBLIC xxsnap_overlay_renderer
    PRIVATE xxsnap_windows_build_configuration user32 gdi32 imm32
)

add_library(
    xxsnap_overlay_host
    src/overlay/OverlayHost.cpp
)
target_compile_features(xxsnap_overlay_host PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_overlay_host
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)
target_link_libraries(
    xxsnap_overlay_host
    PUBLIC xxsnap_overlay_window xxsnap_selection_model
           xxsnap_shape_editor_controller
    PRIVATE xxsnap_selection_composer xxsnap_annotation_composer
            xxsnap_windows_build_configuration user32 comdlg32
)
target_link_libraries(
    xxsnap_pinned_image_host
    PRIVATE xxsnap_overlay_host xxsnap_annotation_composer
            xxsnap_display_topology
)

add_library(
    xxsnap_full_screen_capture_preview_host
    src/fullscreen/FullScreenCapturePreviewHost.cpp
)
target_compile_features(
    xxsnap_full_screen_capture_preview_host PUBLIC cxx_std_17
)
target_include_directories(
    xxsnap_full_screen_capture_preview_host
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_full_screen_capture_preview_host
    PUBLIC xxsnap_pinned_image_host xxsnap_overlay_host
    PRIVATE xxsnap_preferences_settings xxsnap_annotation_composer
            xxsnap_display_topology
            xxsnap_windows_build_configuration user32 gdi32 comdlg32
)

add_library(
    xxsnap_quirc
    third_party/quirc/decode.c
    third_party/quirc/identify.c
    third_party/quirc/quirc.c
    third_party/quirc/version_db.c
)
target_include_directories(
    xxsnap_quirc PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/third_party/quirc"
)
if(MSVC)
    target_compile_options(xxsnap_quirc PRIVATE /wd4244 /wd4018 /wd4100 /wd4457 /wd4389)
endif()

add_library(
    xxsnap_ocr_engine
    src/ocr/OcrEngine.cpp
    src/ocr/QrCodeEngine.cpp
)
target_compile_features(xxsnap_ocr_engine PUBLIC cxx_std_20)
target_include_directories(
    xxsnap_ocr_engine PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_ocr_engine
    PUBLIC snipory_core_portable
    PRIVATE xxsnap_quirc
    PRIVATE xxsnap_windows_build_configuration ole32
)
if(XXSNAP_WINDOWS_FAMILY STREQUAL "modern")
    target_link_libraries(xxsnap_ocr_engine PRIVATE windowsapp)
endif()

add_library(xxsnap_capture_sound src/app/CaptureSound.cpp)
target_compile_features(xxsnap_capture_sound PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_capture_sound
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)
target_link_libraries(
    xxsnap_capture_sound
    PRIVATE xxsnap_windows_build_configuration winmm
)

add_library(
    xxsnap_ocr_capture_host
    src/ocr/OcrCaptureHost.cpp
    src/ocr/OcrResultPresenter.cpp
)
target_compile_features(xxsnap_ocr_capture_host PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_ocr_capture_host PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_ocr_capture_host
    PUBLIC xxsnap_ocr_engine xxsnap_overlay_host
    PRIVATE xxsnap_dxgi_capture_backend xxsnap_gdi_capture_backend
            xxsnap_fallback_capture_backend xxsnap_display_topology
            xxsnap_selection_composer xxsnap_clipboard_writer
            xxsnap_preferences_settings xxsnap_capture_sound
            xxsnap_windows_build_configuration
            ole32 user32 gdi32
)

add_library(xxsnap_single_instance src/app/SingleInstance.cpp)
target_compile_features(xxsnap_single_instance PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_single_instance
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_single_instance
    PRIVATE xxsnap_windows_build_configuration user32
)

add_library(xxsnap_tray_icon src/app/TrayIcon.cpp)
target_compile_features(xxsnap_tray_icon PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_tray_icon
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_tray_icon
    PRIVATE xxsnap_windows_build_configuration user32 shell32
)

add_library(xxsnap_hot_key_registrar src/app/HotKeyRegistrar.cpp)
target_compile_features(xxsnap_hot_key_registrar PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_hot_key_registrar
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_hot_key_registrar
    PRIVATE xxsnap_windows_build_configuration user32
)

add_library(xxsnap_hot_key_settings src/app/HotKeySettings.cpp)
target_compile_features(xxsnap_hot_key_settings PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_hot_key_settings
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_hot_key_settings
    PUBLIC xxsnap_hot_key_registrar xxsnap_preferences_settings
    PRIVATE xxsnap_windows_build_configuration
)

add_library(xxsnap_launch_at_login src/app/LaunchAtLogin.cpp)
target_compile_features(xxsnap_launch_at_login PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_launch_at_login
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_launch_at_login
    PRIVATE xxsnap_windows_build_configuration advapi32
)

add_library(xxsnap_preferences_settings src/app/PreferencesSettings.cpp)
target_compile_features(xxsnap_preferences_settings PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_preferences_settings
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_preferences_settings
    PRIVATE xxsnap_windows_build_configuration advapi32
)

add_library(xxsnap_shortcut_feedback src/app/ShortcutFeedback.cpp)
target_compile_features(xxsnap_shortcut_feedback PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_shortcut_feedback
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_shortcut_feedback
    PUBLIC xxsnap_hot_key_registrar xxsnap_preferences_settings
    PRIVATE xxsnap_windows_build_configuration user32 gdi32
)

add_library(xxsnap_preferences_window src/app/PreferencesWindow.cpp)
target_compile_features(xxsnap_preferences_window PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_preferences_window
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
    PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)
target_link_libraries(
    xxsnap_preferences_window
    PUBLIC xxsnap_preferences_settings
    PRIVATE xxsnap_launch_at_login xxsnap_windows_build_configuration
            user32 gdi32 shell32 version
            windowscodecs ole32
)

add_library(xxsnap_help_window src/app/HelpWindow.cpp)
target_compile_features(xxsnap_help_window PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_help_window
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_help_window
    PRIVATE xxsnap_windows_build_configuration user32 gdi32
)

add_library(xxsnap_diagnostic_support src/diagnostics/DiagnosticSupport.cpp)
target_compile_features(xxsnap_diagnostic_support PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_diagnostic_support
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_diagnostic_support
    PRIVATE xxsnap_windows_build_configuration
            user32 shell32 comdlg32 version
)

add_library(
    xxsnap_capture_session_coordinator
    src/session/CaptureMemoryPlan.cpp
    src/session/CaptureSessionCoordinator.cpp
)
target_compile_features(xxsnap_capture_session_coordinator PUBLIC cxx_std_17)
target_include_directories(
    xxsnap_capture_session_coordinator
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(
    xxsnap_capture_session_coordinator
    PUBLIC xxsnap_capture_session_state xxsnap_capture_backend
           xxsnap_selection_composer xxsnap_overlay_host
)

add_executable(
    xxsnap_windows WIN32
    src/app/AppHost.cpp
    src/app/WinMain.cpp
)
target_compile_features(xxsnap_windows PRIVATE cxx_std_17)
target_include_directories(
    xxsnap_windows
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)
target_link_libraries(
    xxsnap_windows
    PRIVATE
        xxsnap_capture_session_coordinator
        xxsnap_display_topology
        xxsnap_dxgi_capture_backend
        xxsnap_gdi_capture_backend
        xxsnap_fallback_capture_backend
        xxsnap_scroll_capture_host
        xxsnap_pinned_image_host
        xxsnap_full_screen_capture_preview_host
        xxsnap_ocr_capture_host
        xxsnap_selection_composer
        xxsnap_annotation_composer
        xxsnap_png_writer
        xxsnap_clipboard_writer
        xxsnap_single_instance
        xxsnap_tray_icon
        xxsnap_hot_key_registrar
        xxsnap_hot_key_settings
        xxsnap_preferences_settings
        xxsnap_shortcut_feedback
        xxsnap_capture_sound
        xxsnap_preferences_window
        xxsnap_help_window
        xxsnap_diagnostic_support
        xxsnap_visual_resources
        xxsnap_windows_build_configuration
        comdlg32
        ole32
        user32
)
if(XXSNAP_WINDOWS_FAMILY STREQUAL "legacy")
    if(NOT XXSNAP_WINDOWS7_SUBSYSTEM_VERSION STREQUAL "6.01")
        message(FATAL_ERROR
            "Legacy Windows builds require subsystem version 6.01"
        )
    endif()
    target_link_options(
        xxsnap_windows PRIVATE "/SUBSYSTEM:WINDOWS,6.01"
    )
endif()

if(BUILD_TESTING)
    add_executable(
        xxsnap_windows_source_encoding_test
        tests/TestWindowsSourceEncoding.cpp
    )
    target_compile_features(
        xxsnap_windows_source_encoding_test PRIVATE cxx_std_17
    )
    add_test(
        NAME windows_source_encoding
        COMMAND xxsnap_windows_source_encoding_test
    )

    add_executable(xxsnap_build_configuration_test tests/TestBuildConfiguration.cpp)
    target_compile_features(xxsnap_build_configuration_test PRIVATE cxx_std_20)
    target_link_libraries(xxsnap_build_configuration_test
        PRIVATE xxsnap_windows_build_configuration
    )
    add_test(NAME build_configuration COMMAND xxsnap_build_configuration_test)

    add_executable(
        xxsnap_capture_session_state_test
        tests/TestCaptureSessionStateMachine.cpp
    )
    target_compile_features(xxsnap_capture_session_state_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_capture_session_state_test
        PRIVATE xxsnap_capture_session_state
    )
    add_test(
        NAME capture_session_state
        COMMAND xxsnap_capture_session_state_test
    )

    add_executable(
        xxsnap_selection_model_test
        tests/TestSelectionModel.cpp
    )
    target_compile_features(xxsnap_selection_model_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_selection_model_test
        PRIVATE xxsnap_selection_model
    )
    add_test(NAME selection_model COMMAND xxsnap_selection_model_test)

    add_executable(
        xxsnap_pinned_image_geometry_test
        tests/TestPinnedImageGeometry.cpp
    )
    target_compile_features(
        xxsnap_pinned_image_geometry_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_pinned_image_geometry_test
        PRIVATE xxsnap_pinned_image_host
                xxsnap_full_screen_capture_preview_host
    )
    add_test(
        NAME pinned_image_geometry
        COMMAND xxsnap_pinned_image_geometry_test
    )

    add_executable(
        xxsnap_display_topology_test
        tests/TestDisplayTopology.cpp
    )
    target_compile_features(xxsnap_display_topology_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_display_topology_test
        PRIVATE xxsnap_display_topology
    )
    add_test(NAME display_topology COMMAND xxsnap_display_topology_test)

    add_executable(
        xxsnap_gdi_capture_test
        tests/TestGdiCaptureBackend.cpp
    )
    target_compile_features(xxsnap_gdi_capture_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_gdi_capture_test
        PRIVATE xxsnap_gdi_capture_backend
    )
    add_test(NAME gdi_capture COMMAND xxsnap_gdi_capture_test)

    if(XXSNAP_WINDOWS_FAMILY STREQUAL "modern")
        add_executable(
            xxsnap_fallback_capture_test
            tests/TestFallbackCaptureBackend.cpp
        )
        target_compile_features(xxsnap_fallback_capture_test PRIVATE cxx_std_17)
        target_link_libraries(
            xxsnap_fallback_capture_test
            PRIVATE xxsnap_fallback_capture_backend xxsnap_dxgi_capture_backend
                    xxsnap_windows_build_configuration
        )
        add_test(NAME fallback_capture COMMAND xxsnap_fallback_capture_test)
    endif()

    add_executable(
        xxsnap_legacy_runtime_apis_test
        tests/TestLegacyRuntimeApis.cpp
        src/capture/FallbackCaptureBackend.cpp
    )
    target_compile_features(
        xxsnap_legacy_runtime_apis_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_legacy_runtime_apis_test
        PRIVATE xxsnap_capture_backend
    )
    target_compile_definitions(
        xxsnap_legacy_runtime_apis_test
        PRIVATE XXSNAP_LEGACY _WIN32_WINNT=0x0601 WINVER=0x0601
    )
    add_test(
        NAME legacy_runtime_apis
        COMMAND xxsnap_legacy_runtime_apis_test
    )

    add_executable(
        xxsnap_visual_style_test
        tests/TestVisualStyleCatalog.cpp
    )
    target_compile_features(xxsnap_visual_style_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_visual_style_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    add_dependencies(xxsnap_visual_style_test xxsnap_visual_assets)
    add_test(NAME visual_style COMMAND xxsnap_visual_style_test)

    add_executable(
        xxsnap_toolbar_catalog_test
        tests/TestToolbarCatalog.cpp
    )
    target_compile_features(xxsnap_toolbar_catalog_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_toolbar_catalog_test
        PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
            "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    )
    target_link_libraries(
        xxsnap_toolbar_catalog_test
        PRIVATE xxsnap_visual_resources windowscodecs ole32
    )
    add_dependencies(xxsnap_toolbar_catalog_test xxsnap_visual_assets)
    add_test(NAME toolbar_catalog COMMAND xxsnap_toolbar_catalog_test)

    add_executable(
        xxsnap_toolbar_layout_test
        tests/TestToolbarLayout.cpp
    )
    target_compile_features(xxsnap_toolbar_layout_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_toolbar_layout_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_toolbar_layout_test
        PRIVATE xxsnap_toolbar_layout
    )
    add_test(NAME toolbar_layout COMMAND xxsnap_toolbar_layout_test)

    add_executable(
        xxsnap_toolbar_state_test
        tests/TestToolbarState.cpp
    )
    target_compile_features(xxsnap_toolbar_state_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_toolbar_state_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_toolbar_state_test
        PRIVATE xxsnap_toolbar_state
    )
    add_test(NAME toolbar_state COMMAND xxsnap_toolbar_state_test)

    add_executable(
        xxsnap_annotation_types_test
        tests/TestAnnotationTypes.cpp
    )
    target_compile_features(xxsnap_annotation_types_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_annotation_types_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    add_test(NAME annotation_types COMMAND xxsnap_annotation_types_test)

    add_executable(
        xxsnap_annotation_document_test
        tests/TestAnnotationDocument.cpp
    )
    target_compile_features(xxsnap_annotation_document_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_annotation_document_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_annotation_document_test
        PRIVATE xxsnap_annotation_document
    )
    add_test(NAME annotation_document COMMAND xxsnap_annotation_document_test)

    add_executable(
        xxsnap_shape_interaction_test
        tests/TestShapeInteraction.cpp
    )
    target_compile_features(xxsnap_shape_interaction_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_shape_interaction_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_shape_interaction_test
        PRIVATE xxsnap_shape_interaction
    )
    add_test(NAME shape_interaction COMMAND xxsnap_shape_interaction_test)

    add_executable(
        xxsnap_shape_options_test
        tests/TestShapeOptions.cpp
    )
    target_compile_features(xxsnap_shape_options_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_shape_options_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_shape_options_test
        PRIVATE xxsnap_shape_options
    )
    add_test(NAME shape_options COMMAND xxsnap_shape_options_test)

    add_executable(
        xxsnap_annotation_renderer_test
        tests/TestAnnotationRenderer.cpp
    )
    target_compile_features(xxsnap_annotation_renderer_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_annotation_renderer_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_annotation_renderer_test
        PRIVATE xxsnap_annotation_renderer d2d1 windowscodecs ole32
    )
    add_test(NAME annotation_renderer COMMAND xxsnap_annotation_renderer_test)

    add_executable(
        xxsnap_shape_editor_controller_test
        tests/TestShapeEditorController.cpp
    )
    target_compile_features(xxsnap_shape_editor_controller_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_shape_editor_controller_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_shape_editor_controller_test
        PRIVATE xxsnap_shape_editor_controller
    )
    add_test(NAME shape_editor_controller COMMAND xxsnap_shape_editor_controller_test)

    add_executable(
        xxsnap_overlay_layout_test
        tests/TestOverlayLayout.cpp
    )
    target_compile_features(xxsnap_overlay_layout_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_overlay_layout_test
        PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
            "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    )
    target_link_libraries(
        xxsnap_overlay_layout_test
        PRIVATE xxsnap_overlay_renderer xxsnap_overlay_window
                xxsnap_display_topology xxsnap_windows_build_configuration
    )
    add_test(NAME overlay_layout COMMAND xxsnap_overlay_layout_test)

    add_executable(
        xxsnap_overlay_input_test
        tests/TestOverlayInputRouting.cpp
    )
    target_compile_features(xxsnap_overlay_input_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_overlay_input_test
        PRIVATE xxsnap_overlay_host xxsnap_windows_build_configuration
    )
    add_test(NAME overlay_input COMMAND xxsnap_overlay_input_test)
    add_custom_target(
        xxsnap_overlay_input_verification
        DEPENDS
            xxsnap_overlay_input_test
            xxsnap_overlay_layout_test
            xxsnap_selection_model_test
    )

    add_executable(
        xxsnap_app_entry_services_test
        tests/TestAppEntryServices.cpp
    )
    target_compile_features(xxsnap_app_entry_services_test PRIVATE cxx_std_17)
    target_include_directories(
        xxsnap_app_entry_services_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_app_entry_services_test
        PRIVATE xxsnap_single_instance xxsnap_tray_icon
                xxsnap_hot_key_registrar xxsnap_windows_build_configuration
                user32 shell32
    )
    add_test(NAME app_entry_services COMMAND xxsnap_app_entry_services_test)

    add_executable(
        xxsnap_preferences_settings_test
        tests/TestPreferencesSettings.cpp
    )
    target_compile_features(xxsnap_preferences_settings_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_preferences_settings_test
        PRIVATE xxsnap_preferences_settings xxsnap_hot_key_settings
                xxsnap_windows_build_configuration
    )
    add_test(NAME preferences_settings COMMAND xxsnap_preferences_settings_test)

    add_executable(
        xxsnap_shortcut_feedback_test tests/TestShortcutFeedback.cpp
    )
    target_compile_features(xxsnap_shortcut_feedback_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_shortcut_feedback_test
        PRIVATE xxsnap_shortcut_feedback xxsnap_windows_build_configuration
    )
    add_test(NAME shortcut_feedback COMMAND xxsnap_shortcut_feedback_test)

    add_executable(
        xxsnap_capture_sound_test tests/TestCaptureSound.cpp
    )
    target_compile_features(xxsnap_capture_sound_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_capture_sound_test
        PRIVATE xxsnap_capture_sound xxsnap_visual_resources
                xxsnap_windows_build_configuration
    )
    add_dependencies(xxsnap_capture_sound_test xxsnap_visual_assets)
    add_test(NAME capture_sound COMMAND xxsnap_capture_sound_test)

    add_executable(
        xxsnap_launch_at_login_test
        tests/TestLaunchAtLogin.cpp
    )
    target_compile_features(xxsnap_launch_at_login_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_launch_at_login_test
        PRIVATE xxsnap_launch_at_login xxsnap_windows_build_configuration
    )
    add_test(NAME launch_at_login COMMAND xxsnap_launch_at_login_test)

    add_executable(
        xxsnap_preferences_window_test
        tests/TestPreferencesWindow.cpp
    )
    target_compile_features(xxsnap_preferences_window_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_preferences_window_test
        PRIVATE xxsnap_preferences_window xxsnap_windows_build_configuration
    )
    add_test(NAME preferences_window COMMAND xxsnap_preferences_window_test)

    add_executable(xxsnap_help_window_test tests/TestHelpWindow.cpp)
    target_compile_features(xxsnap_help_window_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_help_window_test
        PRIVATE xxsnap_help_window xxsnap_windows_build_configuration
    )
    add_test(NAME help_window COMMAND xxsnap_help_window_test)

    add_executable(
        xxsnap_diagnostic_support_test
        tests/TestDiagnosticSupport.cpp
    )
    target_compile_features(xxsnap_diagnostic_support_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_diagnostic_support_test
        PRIVATE xxsnap_diagnostic_support xxsnap_windows_build_configuration
    )
    add_test(NAME diagnostic_support COMMAND xxsnap_diagnostic_support_test)

    add_executable(
        xxsnap_capture_session_coordinator_test
        tests/TestCaptureSessionCoordinator.cpp
    )
    target_compile_features(
        xxsnap_capture_session_coordinator_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_capture_session_coordinator_test
        PRIVATE xxsnap_capture_session_coordinator
                xxsnap_windows_build_configuration
    )
    add_test(
        NAME capture_session_coordinator
        COMMAND xxsnap_capture_session_coordinator_test
    )

    add_executable(
        xxsnap_memory_budget_matrix_test
        tests/TestMemoryBudgetMatrix.cpp
    )
    target_compile_features(
        xxsnap_memory_budget_matrix_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_memory_budget_matrix_test
        PRIVATE xxsnap_capture_session_coordinator
                xxsnap_windows_build_configuration
    )
    add_test(NAME memory_budget_matrix COMMAND xxsnap_memory_budget_matrix_test)

    add_executable(
        xxsnap_selection_composer_test
        tests/TestSelectionComposer.cpp
    )
    target_compile_features(xxsnap_selection_composer_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_selection_composer_test
        PRIVATE xxsnap_selection_composer xxsnap_display_topology
    )
    add_test(NAME selection_composer COMMAND xxsnap_selection_composer_test)

    add_executable(
        xxsnap_scroll_capture_session_test
        tests/TestScrollCaptureSession.cpp
    )
    target_compile_features(
        xxsnap_scroll_capture_session_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_scroll_capture_session_test
        PRIVATE xxsnap_scroll_capture_session
    )
    add_test(
        NAME scroll_capture_session
        COMMAND xxsnap_scroll_capture_session_test
    )

    add_executable(
        xxsnap_long_image_editor_geometry_test
        tests/TestLongImageEditorGeometry.cpp
    )
    target_compile_features(
        xxsnap_long_image_editor_geometry_test PRIVATE cxx_std_17
    )
    target_include_directories(
        xxsnap_long_image_editor_geometry_test
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(
        xxsnap_long_image_editor_geometry_test
        PRIVATE snipory_core_portable
    )
    add_test(
        NAME long_image_editor_geometry
        COMMAND xxsnap_long_image_editor_geometry_test
    )

    add_executable(
        xxsnap_scroll_capture_target_detector_test
        tests/TestScrollCaptureTargetDetector.cpp
    )
    target_compile_features(
        xxsnap_scroll_capture_target_detector_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_scroll_capture_target_detector_test
        PRIVATE xxsnap_scroll_capture_target_detector
    )
    add_test(
        NAME scroll_capture_target_detector
        COMMAND xxsnap_scroll_capture_target_detector_test
    )

    add_executable(
        xxsnap_scroll_region_capturer_test
        tests/TestScrollRegionCapturer.cpp
    )
    target_compile_features(
        xxsnap_scroll_region_capturer_test PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_scroll_region_capturer_test
        PRIVATE xxsnap_scroll_region_capturer
    )
    add_test(
        NAME scroll_region_capturer
        COMMAND xxsnap_scroll_region_capturer_test
    )

    add_executable(
        xxsnap_annotation_composer_test
        tests/TestAnnotationComposer.cpp
    )
    target_compile_features(xxsnap_annotation_composer_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_annotation_composer_test
        PRIVATE xxsnap_annotation_composer
    )
    add_test(NAME annotation_composer COMMAND xxsnap_annotation_composer_test)

    add_executable(
        xxsnap_clipboard_writer_test
        tests/TestClipboardWriter.cpp
    )
    target_compile_features(xxsnap_clipboard_writer_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_clipboard_writer_test
        PRIVATE xxsnap_clipboard_writer xxsnap_windows_build_configuration
    )
    add_test(NAME clipboard_writer COMMAND xxsnap_clipboard_writer_test)

    configure_file(
        tests/fixtures/qr-xxsnap-2026.bmp
        "${CMAKE_CURRENT_BINARY_DIR}/fixtures/qr-xxsnap-2026.bmp"
        COPYONLY
    )
    add_executable(
        xxsnap_ocr_engine_test
        tests/TestOcrEngine.cpp
    )
    target_compile_features(xxsnap_ocr_engine_test PRIVATE cxx_std_20)
    target_link_libraries(
        xxsnap_ocr_engine_test
        PRIVATE xxsnap_ocr_engine xxsnap_windows_build_configuration user32 gdi32
    )
    add_test(NAME ocr_engine COMMAND xxsnap_ocr_engine_test)
    set_tests_properties(
        ocr_engine PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fixtures"
    )

    add_executable(
        xxsnap_png_writer_test
        tests/TestPngWriter.cpp
    )
    target_compile_features(xxsnap_png_writer_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_png_writer_test
        PRIVATE xxsnap_png_writer xxsnap_windows_build_configuration
                windowscodecs ole32
    )
    add_test(NAME png_writer COMMAND xxsnap_png_writer_test)

    add_executable(
        xxsnap_interactive_session_launcher EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/launch-interactive.cpp
    )
    target_compile_features(
        xxsnap_interactive_session_launcher PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_session_launcher PRIVATE advapi32 userenv wtsapi32
    )

    add_executable(
        xxsnap_interactive_startup_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-startup.cpp
    )
    target_compile_features(
        xxsnap_interactive_startup_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(xxsnap_interactive_startup_verifier PRIVATE user32)

    add_executable(
        xxsnap_interactive_pin_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-pin.cpp
    )
    target_compile_features(xxsnap_interactive_pin_verifier PRIVATE cxx_std_17)
    target_link_libraries(xxsnap_interactive_pin_verifier PRIVATE user32)

    add_executable(
        xxsnap_interactive_fullscreen_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-fullscreen.cpp
    )
    target_compile_features(
        xxsnap_interactive_fullscreen_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_fullscreen_verifier PRIVATE user32 gdi32
    )

    add_executable(
        xxsnap_interactive_ocr_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-ocr.cpp
    )
    target_compile_features(
        xxsnap_interactive_ocr_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_ocr_verifier PRIVATE user32 gdi32
    )

    add_executable(
        xxsnap_interactive_teaching_pen_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-teaching-pen.cpp
    )
    target_compile_features(
        xxsnap_interactive_teaching_pen_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_teaching_pen_verifier PRIVATE user32 gdi32
    )

    add_executable(
        xxsnap_interactive_preferences_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-preferences.cpp
    )
    target_compile_features(
        xxsnap_interactive_preferences_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_preferences_verifier
        PRIVATE xxsnap_preferences_settings user32 gdi32 advapi32
    )

    add_executable(
        xxsnap_interactive_help_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-help.cpp
    )
    target_compile_features(
        xxsnap_interactive_help_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_help_verifier PRIVATE user32 gdi32
    )

    add_executable(
        xxsnap_interactive_shortcut_feedback_verifier EXCLUDE_FROM_ALL
        ${CMAKE_SOURCE_DIR}/tools/windows/verify-interactive-shortcut-feedback.cpp
    )
    target_compile_features(
        xxsnap_interactive_shortcut_feedback_verifier PRIVATE cxx_std_17
    )
    target_link_libraries(
        xxsnap_interactive_shortcut_feedback_verifier PRIVATE user32
    )
endif()

set(xxsnap_capture_session_targets
    xxsnap_capture_session_state
    xxsnap_selection_model
    xxsnap_display_topology
    xxsnap_gdi_capture_backend
    xxsnap_dxgi_capture_backend
    xxsnap_fallback_capture_backend
    xxsnap_selection_composer
    xxsnap_scroll_capture_session
    xxsnap_scroll_capture_target_detector
    xxsnap_scroll_region_capturer
    xxsnap_scroll_capture_host
    xxsnap_annotation_composer
    xxsnap_png_writer
    xxsnap_clipboard_writer
    xxsnap_toolbar_layout
    xxsnap_toolbar_state
    xxsnap_annotation_document
    xxsnap_shape_interaction
    xxsnap_shape_options
    xxsnap_annotation_renderer
    xxsnap_shape_editor_controller
    xxsnap_overlay_renderer
    xxsnap_overlay_window
    xxsnap_overlay_host
    xxsnap_pinned_image_host
    xxsnap_full_screen_capture_preview_host
    xxsnap_quirc
    xxsnap_ocr_engine
    xxsnap_ocr_capture_host
    xxsnap_single_instance
    xxsnap_tray_icon
    xxsnap_hot_key_registrar
    xxsnap_hot_key_settings
    xxsnap_launch_at_login
    xxsnap_preferences_settings
    xxsnap_shortcut_feedback
    xxsnap_preferences_window
    xxsnap_help_window
    xxsnap_diagnostic_support
    xxsnap_capture_session_coordinator
    xxsnap_windows
)
if(BUILD_TESTING)
    list(APPEND xxsnap_capture_session_targets xxsnap_capture_session_state_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_selection_model_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_pinned_image_geometry_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_display_topology_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_gdi_capture_test)
    if(XXSNAP_WINDOWS_FAMILY STREQUAL "modern")
        list(APPEND xxsnap_capture_session_targets xxsnap_fallback_capture_test)
    endif()
    list(APPEND xxsnap_capture_session_targets xxsnap_visual_style_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_toolbar_catalog_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_toolbar_layout_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_toolbar_state_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_annotation_types_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_annotation_document_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_shape_interaction_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_shape_options_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_annotation_renderer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_shape_editor_controller_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_overlay_layout_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_overlay_input_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_app_entry_services_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_preferences_settings_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_shortcut_feedback_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_launch_at_login_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_preferences_window_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_help_window_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_diagnostic_support_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_capture_session_coordinator_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_memory_budget_matrix_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_selection_composer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_scroll_capture_session_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_scroll_capture_target_detector_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_scroll_region_capturer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_annotation_composer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_clipboard_writer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_ocr_engine_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_png_writer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_interactive_session_launcher)
    list(APPEND xxsnap_capture_session_targets xxsnap_interactive_startup_verifier)
    list(APPEND xxsnap_capture_session_targets xxsnap_interactive_pin_verifier)
    list(APPEND xxsnap_capture_session_targets xxsnap_interactive_fullscreen_verifier)
    list(APPEND xxsnap_capture_session_targets xxsnap_interactive_ocr_verifier)
    list(APPEND xxsnap_capture_session_targets
        xxsnap_interactive_teaching_pen_verifier)
    list(APPEND xxsnap_capture_session_targets
        xxsnap_interactive_shortcut_feedback_verifier)
endif()

if(MSVC)
    foreach(target IN LISTS xxsnap_capture_session_targets)
        target_compile_options(${target} PRIVATE /W4 /WX /permissive-)
    endforeach()
else()
    foreach(target IN LISTS xxsnap_capture_session_targets)
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endforeach()
endif()
