cmake_minimum_required(VERSION 3.24)

# Single source of truth for the application version lives in the root VERSION file.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" _tsuki_file_version)
string(STRIP "${_tsuki_file_version}" _tsuki_file_version)
if(_tsuki_file_version STREQUAL "")
    message(FATAL_ERROR "VERSION file must not be empty")
endif()
string(REGEX MATCH "^[0-9]+(\\.[0-9]+)*" _tsuki_cmake_version "${_tsuki_file_version}")
if(_tsuki_cmake_version STREQUAL "")
    set(_tsuki_cmake_version "0.0.0")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/VERSION"
)

project(tsuki VERSION ${_tsuki_cmake_version} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)
find_package(ZLIB REQUIRED)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    Qml
    Quick
    QuickControls2
    Sql
    Network
    Svg
    Concurrent
    Test
)

set(TSUKI_CORE_SOURCES
    src/core/Models.h
    src/core/AppSettings.h
    src/core/AppSettings.cpp
    src/core/DatabaseManager.h
    src/core/DatabaseManager.cpp
    src/services/DownloadManager.h
    src/services/DownloadManager.cpp
    src/services/RunnerManager.h
    src/services/RunnerManager.cpp
    src/services/PrefixManager.h
    src/services/PrefixManager.cpp
    src/services/WinetricksManager.h
    src/services/WinetricksManager.cpp
    src/services/UinputXboxDevice.h
    src/services/UinputXboxDevice.cpp
    src/services/ControllerManager.h
    src/services/ControllerManager.cpp
    src/services/SteamGridDbService.h
    src/services/SteamGridDbService.cpp
    src/services/DiagnosticsManager.h
    src/services/DiagnosticsManager.cpp
    src/services/LaunchPipeline.h
    src/services/LaunchPipeline.cpp
    src/services/EpicManifestParser.h
    src/services/EpicManifestParser.cpp
    src/services/EpicService.h
    src/services/EpicService.cpp
    src/services/GameManager.h
    src/services/GameManager.cpp
    src/ui/UiController.h
    src/ui/UiController.cpp
)

add_library(tsuki_core STATIC ${TSUKI_CORE_SOURCES})
target_include_directories(tsuki_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(tsuki_core PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Sql
    Qt6::Network
    Qt6::Svg
    Qt6::Concurrent
    PkgConfig::SDL2
    ZLIB::ZLIB
)

# Leave TSUKI_VERSION empty by default so updates to the root VERSION file
# propagate without getting pinned in CMakeCache; packagers can still pass
# -DTSUKI_VERSION=<ver> on the CLI. Also migrate any stale cached default left
# behind by older CMakeLists that stored PROJECT_VERSION directly in the cache.
if(DEFINED TSUKI_VERSION AND NOT TSUKI_VERSION STREQUAL "")
    get_property(_tsuki_ver_help CACHE TSUKI_VERSION PROPERTY HELPSTRING)
    if(_tsuki_ver_help STREQUAL "Application display version" AND TSUKI_VERSION VERSION_LESS _tsuki_file_version)
        set(TSUKI_VERSION "" CACHE STRING "Optional override for application display version (defaults to VERSION file)" FORCE)
    endif()
endif()
set(TSUKI_VERSION "" CACHE STRING "Optional override for application display version (defaults to VERSION file)")
if(NOT TSUKI_VERSION STREQUAL "")
    set(_TSUKI_EFFECTIVE_VERSION "${TSUKI_VERSION}")
    set(_TSUKI_VERSION_OVERRIDDEN 1)
else()
    set(_TSUKI_EFFECTIVE_VERSION "${_tsuki_file_version}")
    set(_TSUKI_VERSION_OVERRIDDEN 0)
endif()

add_executable(tsuki
    src/main.cpp
    resources/resources.qrc
    resources/fonts.qrc
)
target_compile_definitions(tsuki PRIVATE TSUKI_VERSION="${_TSUKI_EFFECTIVE_VERSION}")
target_link_libraries(tsuki PRIVATE tsuki_core)

enable_testing()
add_executable(tsuki_tests
    tests/test_tsuki.cpp
    resources/resources.qrc
    resources/fonts.qrc
)
target_compile_definitions(tsuki_tests PRIVATE
    TSUKI_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
    TSUKI_VERSION="${_TSUKI_EFFECTIVE_VERSION}"
    TSUKI_DEFAULT_VERSION="${_tsuki_file_version}"
    TSUKI_PROJECT_VERSION="${PROJECT_VERSION}"
    TSUKI_VERSION_OVERRIDDEN=${_TSUKI_VERSION_OVERRIDDEN}
)
target_link_libraries(tsuki_tests PRIVATE tsuki_core Qt6::Test)
add_test(NAME TsukiUnitTests COMMAND tsuki_tests)
set_tests_properties(TsukiUnitTests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

include(GNUInstallDirs)

install(TARGETS tsuki RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

# Desktop launcher and AppStream metadata
install(FILES packaging/desktop/io.github.muzammilshafique.tsuki.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES packaging/metainfo/io.github.muzammilshafique.tsuki.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)

# Hicolor scalable SVG icon
install(FILES resources/icons/brand/tsuki.svg
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
        RENAME io.github.muzammilshafique.tsuki.svg)

# udev rules and kernel module autoload for unprivileged controller emulation (/dev/uinput)
option(INSTALL_UDEV_RULES "Install udev rules for /dev/uinput controller emulation" ON)
if(INSTALL_UDEV_RULES)
    set(UDEV_RULES_DIR "lib/udev/rules.d" CACHE PATH "Directory for udev rules installation")
    install(FILES packaging/udev/70-tsuki-uinput.rules
            DESTINATION ${UDEV_RULES_DIR})
    set(MODULES_LOAD_DIR "lib/modules-load.d" CACHE PATH "Directory for modules-load configuration")
    install(FILES packaging/udev/tsuki-uinput.conf
            DESTINATION ${MODULES_LOAD_DIR})
endif()

