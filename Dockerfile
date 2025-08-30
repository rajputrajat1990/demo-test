# Minimal container for Phase 1 setup only
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates curl git jq bash \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# Default command just prints help
CMD ["bash", "-lc", "echo 'Use docker run -v $PWD:/work -w /work <image> bash -lc \"scripts/setup.sh\"' "]
