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

install(TARGETS tsuki RUNTIME DESTINATION bin)

