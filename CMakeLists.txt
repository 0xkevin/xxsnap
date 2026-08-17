cmake_minimum_required(VERSION 3.28)
project(xxsnap LANGUAGES C CXX)

include(CTest)

option(XXSNAP_BUILD_QT_CORE "Build the existing Qt-dependent core" ON)

add_subdirectory(core)

if(WIN32)
    add_subdirectory(platforms/win)
endif()
