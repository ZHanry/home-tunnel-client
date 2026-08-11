# HomeDesk platform launchers consume generated brand values from the monorepo config.
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(HOMEDESK_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/homedesk-generated")
file(MAKE_DIRECTORY "${HOMEDESK_GENERATED_DIR}")

execute_process(
  COMMAND "${Python3_EXECUTABLE}"
          "${CMAKE_CURRENT_LIST_DIR}/brand_config.py"
          --cmake-out "${HOMEDESK_GENERATED_DIR}/homedesk_brand.cmake"
          --header-out "${HOMEDESK_GENERATED_DIR}/homedesk_brand.h"
  RESULT_VARIABLE HOMEDESK_BRAND_RESULT
  ERROR_VARIABLE HOMEDESK_BRAND_ERROR
)
if(NOT HOMEDESK_BRAND_RESULT EQUAL 0)
  message(FATAL_ERROR "HomeDesk brand generation failed: ${HOMEDESK_BRAND_ERROR}")
endif()

include("${HOMEDESK_GENERATED_DIR}/homedesk_brand.cmake")
include_directories("${HOMEDESK_GENERATED_DIR}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_LIST_DIR}/config.toml"
  "${CMAKE_CURRENT_LIST_DIR}/config.toml.example"
  "${CMAKE_CURRENT_LIST_DIR}/brand_config.py"
)
