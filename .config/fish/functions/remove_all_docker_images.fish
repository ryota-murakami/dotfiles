# =============================================================================
# remove_all_docker_images - Remove All Docker Images
# =============================================================================
#
# DESCRIPTION:
#   Removes ALL Docker images from the system.
#   Useful for freeing disk space or starting fresh with Docker.
#
# USAGE:
#   remove_all_docker_images
#
# WARNING:
#   This removes ALL images without confirmation!
#   You'll need to re-pull or rebuild any needed images.
#
# HOW IT WORKS:
#   1. docker images -q : Lists all image IDs
#   2. docker rmi : Removes each image
#
# NOTE:
#   If containers are using images, remove containers first with
#   kill_all_docker_container
#
# DEPENDENCIES:
#   - docker (via OrbStack or Docker Desktop)
#
# EXAMPLE:
#   $ docker images
#   REPOSITORY   TAG       IMAGE ID
#   node         18        abc123456
#   postgres     14        def789012
#
#   $ remove_all_docker_images
#   Deleted: sha256:abc123...
#   Deleted: sha256:def789...
#
#   $ docker images
#   REPOSITORY   TAG   IMAGE ID
#   (empty)
#
# RELATED:
#   - kill_all_docker_container.fish (remove containers first)
#
# =============================================================================
function remove_all_docker_images
    docker rmi (docker images -q)
end
