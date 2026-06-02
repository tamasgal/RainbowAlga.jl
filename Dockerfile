# Reproducible image for building, testing and running RainbowAlga headlessly.
#
# RainbowAlga depends on GLMakie, which needs a real OpenGL context. CI runners have no
# GPU and no X server, so we install Mesa's software rasteriser (llvmpipe) and run the
# GUI against a virtual X display (Xvfb). This recipe is the single source of truth for
# that environment; the CI (.gitlab-ci.yml) installs the same packages.
#
# Build:  docker build -t rainbowalga-ci .
# Test:   docker run --rm -v "$PWD":/work -w /work rainbowalga-ci \
#             xvfb-run -a julia --project=. -e 'using Pkg; Pkg.test()'
FROM julia:1.11-bookworm

# Headless OpenGL: Mesa software GL + Xvfb + the X11 client libraries GLFW dlopens.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git ca-certificates openssh-client \
        xvfb xauth \
        libgl1 libglx-mesa0 libgl1-mesa-dri libglu1-mesa \
        libxrandr2 libxinerama1 libxcursor1 libxi6 libxext6 \
        libx11-6 libxrender1 libxfixes3 libxxf86vm1 \
        libfontconfig1 libfreetype6 \
    && rm -rf /var/lib/apt/lists/*

# Force software rendering (no GPU on CI runners) and let Pkg use the system git.
ENV LIBGL_ALWAYS_SOFTWARE=1 \
    JULIA_PKG_USE_CLI_GIT=true

CMD ["julia"]
