# Offline heightmap generator (development machine only; never shipped in the game).
#   cmake -S tools/world_generation -B build/worldgen -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/worldgen
#   build/worldgen/heightgen tools/world_generation/regions.cfg green_valley game/world/terrain/source
cmake_minimum_required(VERSION 3.16)
project(openworld_worldgen CXX)
set(CMAKE_CXX_STANDARD 17)
include(FetchContent)
# Strict floating point: the same seed gives the same heightmap on every CPU.
set(FASTNOISE2_STRICT_FP ON CACHE BOOL "" FORCE)
set(FASTNOISE2_TOOLS OFF CACHE BOOL "" FORCE)
set(FASTNOISE2_TESTS OFF CACHE BOOL "" FORCE)
FetchContent_Declare(FastNoise2 GIT_REPOSITORY https://github.com/Auburn/FastNoise2.git GIT_TAG v1.1.1)
FetchContent_MakeAvailable(FastNoise2)
add_executable(heightgen heightgen.cpp)
target_link_libraries(heightgen PRIVATE FastNoise)
