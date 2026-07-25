cmake_minimum_required(VERSION 3.22.1)
project("omnircm")

add_library(rcm_injector SHARED rcm_injector.cpp)
target_link_libraries(rcm_injector log)
