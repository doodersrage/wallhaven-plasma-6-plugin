cmake_minimum_required(VERSION 3.16)
project(wallhaven-shortcuts LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(KF6GlobalAccel REQUIRED)
find_package(KF6I18n REQUIRED)
find_package(KF6CoreAddons REQUIRED)

add_executable(wallhaven-shortcuts main.cpp)
target_link_libraries(wallhaven-shortcuts
    Qt6::Core
    KF6::GlobalAccel
    KF6::I18n
    KF6::CoreAddons
)

install(TARGETS wallhaven-shortcuts DESTINATION bin)
