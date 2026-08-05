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

if(BUILD_TESTING)
    add_executable(xxsnap_build_configuration_test tests/TestBuildConfiguration.cpp)
    target_compile_features(xxsnap_build_configuration_test PRIVATE cxx_std_20)
    target_link_libraries(xxsnap_build_configuration_test
        PRIVATE xxsnap_windows_build_configuration
    )
    add_test(NAME build_configuration COMMAND xxsnap_build_configuration_test)
endif()
