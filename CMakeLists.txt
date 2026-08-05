cmake_minimum_required(VERSION 3.28)
project(xxsnap LANGUAGES CXX)

include(CTest)

option(XXSNAP_BUILD_QT_CORE "Build the existing Qt portable core" ON)

if(XXSNAP_BUILD_QT_CORE)
    add_subdirectory(core)
endif()

if(WIN32)
    add_subdirectory(platforms/win)
endif()
