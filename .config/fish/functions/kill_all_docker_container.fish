# =============================================================================
# kill_all_docker_container - Remove All Docker Containers
# =============================================================================
#
# DESCRIPTION:
#   Removes ALL Docker containers (running and stopped).
#   Useful for cleaning up after development or when Docker gets cluttered.
#
# USAGE:
#   kill_all_docker_container
#
# WARNING:
#   This removes ALL containers without confirmation!
#   Running containers will be forcefully stopped.
#
# HOW IT WORKS:
#   1. docker ps -a -q : Lists all container IDs
#   2. docker rm : Removes each container
#
# DEPENDENCIES:
#   - docker (via OrbStack or Docker Desktop)
#
# EXAMPLE:
#   $ docker ps -a
#   CONTAINER ID   IMAGE     ...
#   abc123         nginx     ...
#   def456         postgres  ...
#
#   $ kill_all_docker_container
#   abc123
#   def456
#
#   $ docker ps -a
#   CONTAINER ID   IMAGE   ...
#   (empty)
#
# RELATED:
#   - remove_all_docker_images.fish (remove images)
#
# =============================================================================
function kill_all_docker_container
    docker rm (docker ps -a -q)
end
