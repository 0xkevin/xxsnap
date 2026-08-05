add_library(snipory_core_portable
    src/portable/PixelBuffer.cpp
)
target_compile_features(snipory_core_portable PUBLIC cxx_std_17)
target_include_directories(snipory_core_portable
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

function(snipory_core_add_portable_test target_name test_name source_file)
    add_executable(${target_name} ${source_file})
    target_compile_features(${target_name} PRIVATE cxx_std_17)
    target_link_libraries(${target_name} PRIVATE snipory_core_portable)
    add_test(NAME ${test_name} COMMAND ${target_name})
endfunction()

if(BUILD_TESTING)
    snipory_core_add_portable_test(
        test_portable_geometry
        portable_geometry
        tests/TestPortableGeometry.cpp
    )
    snipory_core_add_portable_test(
        test_pixel_buffer
        pixel_buffer
        tests/TestPixelBuffer.cpp
    )
endif()

if(XXSNAP_BUILD_QT_CORE)
    add_library(snipory_core
        src/annotation/AnnotationRenderer.cpp
        src/scroll/FrameFingerprint.cpp
        src/scroll/ScrollStitchSession.cpp
        src/scroll/VerticalOverlapMatcher.cpp
        src/usecases/SnapshotExportUseCase.cpp
    )
    target_compile_features(snipory_core PUBLIC cxx_std_20)

    find_package(Qt6 REQUIRED COMPONENTS Core Gui)

    target_link_libraries(snipory_core
        PUBLIC
            snipory_core_portable
            Qt6::Core
            Qt6::Gui
    )
    target_include_directories(snipory_core
        PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}/include
    )

    if(APPLE AND CMAKE_OSX_SYSROOT AND EXISTS "${CMAKE_OSX_SYSROOT}/usr/include/c++/v1")
        target_include_directories(snipory_core
            SYSTEM PRIVATE
                ${CMAKE_OSX_SYSROOT}/usr/include/c++/v1
        )
    endif()

    function(snipory_core_add_test target_name source_file)
        add_executable(${target_name} ${source_file})
        set_target_properties(${target_name} PROPERTIES AUTOMOC ON)
        target_link_libraries(${target_name}
            PRIVATE
                snipory_core
                Qt6::Test
                Qt6::Gui
                Qt6::Core
        )

        if(APPLE AND CMAKE_OSX_SYSROOT AND EXISTS "${CMAKE_OSX_SYSROOT}/usr/include/c++/v1")
            target_include_directories(${target_name}
                SYSTEM PRIVATE
                    ${CMAKE_OSX_SYSROOT}/usr/include/c++/v1
            )
        endif()

        add_test(NAME ${target_name} COMMAND ${target_name})
    endfunction()

    if(BUILD_TESTING)
        find_package(Qt6 REQUIRED COMPONENTS Test)

        snipory_core_add_test(test_capture_types tests/TestCaptureTypes.cpp)
        snipory_core_add_test(test_annotation_document tests/TestAnnotationDocument.cpp)
        snipory_core_add_test(test_annotation_renderer tests/TestAnnotationRenderer.cpp)
        snipory_core_add_test(test_selection_geometry tests/TestSelectionGeometry.cpp)
        snipory_core_add_test(test_snapshot_export_use_case tests/TestSnapshotExportUseCase.cpp)
        snipory_core_add_test(test_frame_fingerprint tests/TestFrameFingerprint.cpp)
        snipory_core_add_test(test_vertical_overlap_matcher tests/TestVerticalOverlapMatcher.cpp)
        snipory_core_add_test(test_scroll_stitch_session tests/TestScrollStitchSession.cpp)
    endif()
endif()
