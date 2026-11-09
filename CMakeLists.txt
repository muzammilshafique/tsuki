cmake_minimum_required(VERSION 3.24)
project(tsuki VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Note: .temp/ reference directory is strictly excluded from all targets, resources, and installations.

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)

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
)

add_executable(tsuki
    src/main.cpp
    resources/resources.qrc
)
target_link_libraries(tsuki PRIVATE tsuki_core)

enable_testing()
add_executable(tsuki_tests
    tests/test_tsuki.cpp
)
target_link_libraries(tsuki_tests PRIVATE tsuki_core Qt6::Test)
add_test(NAME TsukiUnitTests COMMAND tsuki_tests)

include(GNUInstallDirs)

install(TARGETS tsuki RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

# Desktop launchers
install(FILES packaging/desktop/io.github.muzammilshafique.tsuki.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES packaging/desktop/tsuki.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# AppStream metadata
install(FILES packaging/metainfo/io.github.muzammilshafique.tsuki.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)

# MIME definitions
install(FILES packaging/mime/tsuki.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/mime/packages)

# Standard hicolor icons
foreach(SIZE 16 24 32 48 64 128 256 512)
    install(FILES resources/icons/hicolor/${SIZE}x${SIZE}/apps/tsuki.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${SIZE}x${SIZE}/apps
            RENAME tsuki.png)
    install(FILES resources/icons/hicolor/${SIZE}x${SIZE}/apps/tsuki.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${SIZE}x${SIZE}/apps
            RENAME io.github.muzammilshafique.tsuki.png)
endforeach()

# Scalable SVG icons
install(FILES resources/icons/brand/tsuki.svg
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
        RENAME tsuki.svg)
install(FILES resources/icons/brand/tsuki.svg
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
        RENAME io.github.muzammilshafique.tsuki.svg)

# Legacy pixmaps for window managers
install(FILES resources/icons/hicolor/256x256/apps/tsuki.png
        DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps
        RENAME tsuki.png)
install(FILES resources/icons/brand/tsuki.svg
        DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps
        RENAME tsuki.svg)

# udev rules for unprivileged controller emulation (/dev/uinput)
option(INSTALL_UDEV_RULES "Install udev rules for /dev/uinput controller emulation" ON)
if(INSTALL_UDEV_RULES)
    set(UDEV_RULES_DIR "lib/udev/rules.d" CACHE PATH "Directory for udev rules installation")
    install(FILES packaging/udev/70-tsuki-uinput.rules
            DESTINATION ${UDEV_RULES_DIR})
    set(MODULES_LOAD_DIR "lib/modules-load.d" CACHE PATH "Directory for modules-load configuration")
    install(FILES packaging/udev/tsuki-uinput.conf
            DESTINATION ${MODULES_LOAD_DIR})
endif()

# CPack packaging configuration
set(CPACK_PACKAGE_NAME "tsuki")
set(CPACK_PACKAGE_VENDOR "Tsuki Project")
set(CPACK_PACKAGE_CONTACT "Muzammil Shafique <muzammil@example.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Native Linux Game Launcher (Wine & Proton)")
set(CPACK_PACKAGE_DESCRIPTION "Tsuki is a modern native Linux game launcher designed for Wine and Proton games with prefix management, runner management, and virtual Xbox controller emulation.")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/muzammilshafique/tsuki")
set(CPACK_PACKAGE_VERSION_MAJOR ${PROJECT_VERSION_MAJOR})
set(CPACK_PACKAGE_VERSION_MINOR ${PROJECT_VERSION_MINOR})
set(CPACK_PACKAGE_VERSION_PATCH ${PROJECT_VERSION_PATCH})
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")

# Debian package settings
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Muzammil Shafique <muzammil@example.com>")
set(CPACK_DEBIAN_PACKAGE_SECTION "games")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "amd64")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS OFF)
set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${CMAKE_CURRENT_SOURCE_DIR}/packaging/debian/postinst;${CMAKE_CURRENT_SOURCE_DIR}/packaging/debian/postrm")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libc6 (>= 2.34), libstdc++6 (>= 11), libqt6core6, libqt6gui6, libqt6widgets6, libqt6qml6, libqt6quick6, libqt6quickcontrols2-6, libqt6sql6, libqt6network6, libqt6svg6, libqt6concurrent6, libsdl2-2.0-0, tar")
set(CPACK_DEBIAN_PACKAGE_SUGGESTS "wine, winetricks, mangohud, gamemode, p7zip-full")
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)

# RPM package settings
set(CPACK_RPM_PACKAGE_LICENSE "GPL-3.0-or-later")
set(CPACK_RPM_PACKAGE_GROUP "Amusements/Games")
set(CPACK_RPM_PACKAGE_ARCHITECTURE "x86_64")
set(CPACK_RPM_PACKAGE_REQUIRES "qt6-qtbase, qt6-qtdeclarative, qt6-qtsvg, SDL2, tar")
set(CPACK_RPM_PACKAGE_SUGGESTS "wine, winetricks, mangohud, gamemode, p7zip")
set(CPACK_RPM_FILE_NAME RPM-DEFAULT)

include(CPack)


