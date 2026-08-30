# Fluent Bit log router with Acme's PHI scrubbing filters baked in.
#
# On Fargate a FireLens sidecar cannot load its config from S3, so the config has to ship
# inside the image. CI builds this and pushes it to the environment's ECR as
# <registry>/<prefix>/fluent-bit:<tag>; env.hcl points the services at it.
FROM public.ecr.aws/aws-observability/aws-for-fluent-bit:stable

COPY scrub.conf /fluent-bit/etc/scrub.conf
COPY scrub.lua  /fluent-bit/etc/scrub.lua
