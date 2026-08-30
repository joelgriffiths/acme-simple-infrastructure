# Repositories this environment's registry holds. Component-level config: identical in
# every environment, so it lives beside the unit rather than in env.hcl.
#
# fluent-bit is our own image, built from modules/ecs-service/fluent-bit/. It carries the
# PHI scrubbing filters and cannot be pulled from upstream.
locals {
  # Must match every image_repo value in compute/ecs/*/app_config.hcl. Several services
  # share an image and differ only by their command: api, worker, scheduler, and rebooking
  # all run "backend", and patient and clinician both run "clinic-web".
  repository_names = ["backend", "clinic-web", "admin", "fluent-bit"]
}
