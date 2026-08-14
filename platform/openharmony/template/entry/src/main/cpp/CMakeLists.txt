# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(template)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(PROJECT_ROOT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../..")
set(NODE_SDK_ROOT "${PROJECT_ROOT_PATH}/third_party/node-openharmony/dist/node-v24.13.0-openharmony-arm64")

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

# 1. Main Godot Entry Library
add_library(entry SHARED napi_init.cpp napi_input.cpp)

target_link_libraries(entry PUBLIC 
    libhilog_ndk.z.so 
    libace_ndk.z.so 
    libnative_window.so 
    libace_napi.z.so 
    librawfile.z.so 
    libnative_vsync.so 
    libohaudio.so 
    libohinputmethod.so 
    libnative_display_manager.so 
    libnative_window_manager.so 
    libnative_drawing.so 
    libudmf.so 
    libpasteboard.so 
    libohfileuri.so
)
target_link_libraries(entry PUBLIC ${NATIVERENDER_ROOT_PATH}/../../../libs/${OHOS_ARCH}/libgodot.so)

# 2. OpenCode Formal Runtime Library (Native Child Process Entrypoint)
if(EXISTS "${NODE_SDK_ROOT}/include/node/node.h")
    include_directories("${NODE_SDK_ROOT}/include/node" "${NATIVERENDER_ROOT_PATH}/opencode")

    add_library(opencode_node_shared SHARED IMPORTED GLOBAL)
    set_target_properties(opencode_node_shared PROPERTIES
        IMPORTED_LOCATION "${NATIVERENDER_ROOT_PATH}/../../../libs/${OHOS_ARCH}/libnode.so.137"
    )

    add_library(opencode_formal_runtime SHARED
        opencode/formal_runtime_bridge.cpp
        opencode/formal_node_embedder.cpp
    )
    set_target_properties(opencode_formal_runtime PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        BUILD_RPATH "$ORIGIN"
        INSTALL_RPATH "$ORIGIN"
        CXX_STANDARD 20
        CXX_STANDARD_REQUIRED ON
    )
    target_link_libraries(opencode_formal_runtime PUBLIC
        opencode_node_shared
        libace_napi.z.so
        libhilog_ndk.z.so
        libchild_process.so
    )
endif()
