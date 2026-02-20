{ settings, ... }:
let
  dev = (settings.sysctlProfiles or { }).dev or { };
in {
  # Large inotify limits are needed by IDEs, language servers, and monorepos.
  "fs.inotify.max_user_watches" = dev.inotifyWatches or 1048576;
  "fs.inotify.max_user_instances" = dev.inotifyInstances or 8192;
  "fs.inotify.max_queued_events" = dev.inotifyQueuedEvents or 32768;

  # Better defaults for large local builds, toolchains, and container-heavy dev.
  "kernel.pid_max" = dev.pidMax or 4194304;

  # Better local network backlog for containers and concurrent dev services.
  "net.core.somaxconn" = dev.somaxconn or 4096;
}
