set(XXSNAP_WINDOWS_FAMILY "modern" CACHE STRING "Windows target family (modern or legacy)")
set_property(CACHE XXSNAP_WINDOWS_FAMILY PROPERTY STRINGS modern legacy)

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
set_property(
    SOURCE resources/xxsnap.rc
    APPEND PROPERTY OBJECT_DEPENDS
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/cancel-capture.png"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/save-to-file.png"
        "${PROJECT_SOURCE_DIR}/platforms/mac/Resources/Icons/copy-to-clipboard.png"
        "${PROJECT_SOURCE_DIR}/platforms/win/resources/icons/Snipory.ico"
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
    xxsnap_overlay_renderer
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
    PUBLIC xxsnap_capture_backend xxsnap_visual_resources
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
    PRIVATE xxsnap_windows_build_configuration user32 gdi32
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
    PRIVATE xxsnap_windows_build_configuration user32
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
        xxsnap_selection_composer
        xxsnap_png_writer
        xxsnap_clipboard_writer
        xxsnap_single_instance
        xxsnap_tray_icon
        xxsnap_hot_key_registrar
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
    xxsnap_overlay_renderer
    xxsnap_overlay_window
    xxsnap_overlay_host
    xxsnap_single_instance
    xxsnap_tray_icon
    xxsnap_hot_key_registrar
    xxsnap_capture_session_coordinator
    xxsnap_windows
)
if(BUILD_TESTING)
    list(APPEND xxsnap_capture_session_targets xxsnap_capture_session_state_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_selection_model_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_display_topology_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_gdi_capture_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_fallback_capture_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_visual_style_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_overlay_layout_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_overlay_input_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_app_entry_services_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_capture_session_coordinator_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_memory_budget_matrix_test)
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
