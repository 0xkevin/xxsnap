set(XXSNAP_WINDOWS_FAMILY "modern" CACHE STRING "Windows target family (modern or legacy)")
set_property(CACHE XXSNAP_WINDOWS_FAMILY PROPERTY STRINGS modern legacy)

if(NOT XXSNAP_WINDOWS_FAMILY STREQUAL "modern" AND
   NOT XXSNAP_WINDOWS_FAMILY STREQUAL "legacy")
    message(FATAL_ERROR
        "Invalid XXSNAP_WINDOWS_FAMILY='${XXSNAP_WINDOWS_FAMILY}'; expected modern or legacy"
    )
endif()

add_library(xxsnap_windows_build_configuration INTERFACE)

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
        xxsnap_display_topology_test
        tests/TestDisplayTopology.cpp
    )
    target_compile_features(xxsnap_display_topology_test PRIVATE cxx_std_17)
    target_link_libraries(
        xxsnap_display_topology_test
        PRIVATE xxsnap_display_topology
    )
    add_test(NAME display_topology COMMAND xxsnap_display_topology_test)
endif()

set(xxsnap_capture_session_targets
    xxsnap_capture_session_state
    xxsnap_display_topology
)
if(BUILD_TESTING)
    list(APPEND xxsnap_capture_session_targets xxsnap_capture_session_state_test)
    list(APPEND xxsnap_capture_session_targets xxsnap_display_topology_test)
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
