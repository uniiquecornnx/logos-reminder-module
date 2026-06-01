cmake_minimum_required(VERSION 3.14)
project(RemindersModulePlugin LANGUAGES CXX)

# Include the Logos Module CMake helper (provided by logos-module-builder).
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found")
endif()

# Define the module. `EXTERNAL_LIBS reminders` wires libreminders (in ./lib)
# into the build, mirroring the calc_module pattern.
logos_module(
    NAME reminders
    SOURCES
        src/reminders_interface.h
        src/reminders_plugin.h
        src/reminders_plugin.cpp
    EXTERNAL_LIBS
        reminders
)
