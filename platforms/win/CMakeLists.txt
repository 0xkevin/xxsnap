set(XXSNAP_WINDOWS_FAMILY "modern" CACHE STRING "Windows target family (modern or legacy)")
set_property(CACHE XXSNAP_WINDOWS_FAMILY PROPERTY STRINGS modern legacy)

if(NOT XXSNAP_WINDOWS_FAMILY STREQUAL "modern" AND
   NOT XXSNAP_WINDOWS_FAMILY STREQUAL "legacy")
    message(FATAL_ERROR
        "Invalid XXSNAP_WINDOWS_FAMILY='${XXSNAP_WINDOWS_FAMILY}'; expected modern or legacy"
    )
endif()

add_library(xxsnap_windows_build_configuration INTERFACE)

enable_language(RC)
add_library(xxsnap_visual_assets OBJECT resources/xxsnap.rc)
target_include_directories(
    xxsnap_visual_assets
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/resources"
        "${PROJECT_SOURCE_DIR}"
)
set_property(
    SOURCE resources/xxsnap.rc
    APPEND PROPERTY OBJECT_DEPENDS
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/cancel-capture.png"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/save-to-file.png"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/copy-to-clipboard.png"
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

if(BUILD_TESTING)
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
        xxsnap_clipboard_writer_test
        tests/TestClipboardWriter.cpp
    )
    target_compile_features(xxsnap_clipboard_writer_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_clipboard_writer_test
        PRIVATE xxsnap_clipboard_writer xxsnap_windows_build_configuration
    )
    add_test(NAME clipboard_writer COMMAND xxsnap_clipboard_writer_test)

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
endif()

set(xxsnap_capture_session_targets
    xxsnap_capture_session_state
    xxsnap_selection_model
    xxsnap_display_topology
    xxsnap_gdi_capture_backend
    xxsnap_dxgi_capture_backend
    xxsnap_fallback_capture_backend
    xxsnap_selection_composer
    xxsnap_png_writer
    xxsnap_clipboard_writer
)
if(BUILD_TESTING)
    list(APPEND xxsnap_capture_session_targets xxsnap_capture_session_state_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_selection_model_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_display_topology_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_gdi_capture_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_fallback_capture_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_visual_style_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_selection_composer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_clipboard_writer_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_png_writer_test)
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
