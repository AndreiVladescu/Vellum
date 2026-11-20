cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# The system unwinder has to come before the Flutter engine in the lookup
# order. Since Flutter 3.50, libflutter_linux_gtk.so leaks ten `_Unwind_*`
# symbols from its static LLVM libunwind (flutter/flutter#196402). Because the
# engine is loaded before libgcc_s, libstdc++ then throws through the engine's
# unwinder, which cannot find a handler in GCC-built code, so any C++ exception
# a plugin catches itself aborts the app instead — flutter_secure_storage does
# exactly that when no keyring can be reached, and Vellum died at startup.
# Naming libgcc_s first (--no-as-needed keeps it although nothing in the runner
# calls it) puts it ahead of the engine in DT_NEEDED, so every `_Unwind_*`
# lookup lands there again. On an engine that exports no unwinder (3.47 and
# earlier, or once the upstream fix ships) it changes nothing: libstdc++ loads
# libgcc_s anyway. Link options go before the libraries on the link line.
# Remove this once the pinned Flutter carries the fix
# (`nm -D --defined-only bundle/lib/libflutter_linux_gtk.so | grep _Unwind_`
# prints nothing).
target_link_options(${BINARY_NAME} PRIVATE
  "LINKER:--push-state,--no-as-needed" "-lgcc_s" "LINKER:--pop-state")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
