# ============================================================
# SLAHMR Dockerfile (multi-stage, dev/prod targets)
# CUDA 12.4 + PyTorch 2.4.0 + PHALP dependency split
# ============================================================

# =========================
# Stage 1: builder-base
# =========================
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04 AS builder-base

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      ffmpeg \
      g++ \
      gcc \
      git \
      libegl1 \
      libgl1 \
      libglib2.0-0 \
      libglu1-mesa \
      libgomp1 \
      libsm6 \
      libxext6 \
      libxrender1 \
      ninja-build \
      pkg-config \
      unzip \
      wget \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

RUN curl -L -o /tmp/miniforge.sh \
      https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh

ENV PATH=/opt/conda/bin:$PATH

RUN conda create -y -n slahmr python=3.10 \
      pip setuptools==59.5.0 \
      mkl==2024.0.* && \
    conda clean -afy

SHELL ["conda", "run", "-n", "slahmr", "/bin/bash", "-c"]

RUN pip install torch==2.4.0 \
      torchvision==0.19.0 \
      torchaudio==2.4.0 \
      --index-url https://download.pytorch.org/whl/cu124

ENV PATH=/opt/conda/bin:$PATH
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=$CUDA_HOME/bin:$PATH
ENV LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0+PTX"

RUN pip install torch-scatter -f https://data.pyg.org/whl/torch-2.4.0+cu124.html

RUN git clone https://github.com/hraesvelgr-k9/4D-Humans.git /tmp/4D-Humans && \
    cd /tmp/4D-Humans && \
    mv setup.py setup.py.~ && \
    cp setup_torch240+cu124.py setup.py && \
    pip install --no-build-isolation .[hmr2] && \
    rm -rf /tmp/4D-Humans
RUN pip install --no-build-isolation \
      'detectron2 @ git+https://github.com/facebookresearch/detectron2.git@02b5c4e'
RUN pip install --no-build-isolation \
      'neural-renderer-pytorch @ git+https://github.com/shubham-goel/NMR.git@e990b3c'
RUN pip install \
      'pytube @ git+https://github.com/pytube/pytube.git' \
      'pyopengl @ git+https://github.com/mmatl/pyopengl.git'
RUN pip install --no-build-isolation \
      'phalp[all] @ git+https://github.com/brjathu/PHALP.git@96f7e6c'

RUN pip install --no-build-isolation \
      'git+https://github.com/nghorbani/configer' \
      'git+https://github.com/mattloper/chumpy' \
      torchgeometry==0.1.2 \
      tensorboard \
      numpy==1.26.4 \
      smplx==0.1.28 \
      pyrender \
      open3d \
      imageio-ffmpeg \
      matplotlib \
      opencv-python \
      scipy \
      scikit-image \
      joblib \
      cython \
      tqdm \
      hydra-core \
      pyyaml \
      gdown \
      dill \
      motmetrics \
      einops \
      mmcv==1.3.9 \
      timm==0.4.9 \
      xtcocotools \
      pandas==1.4.0 \
      'scenedetect[opencv]' \
      av

# NOTE: ViTPose and DROID-SLAM require the source tree to be mounted.
# In dev mode these are installed by entrypoint.dev.sh on first boot.
# In prod mode they are expected to be pre-installed via setup.sh before
# building, or copied into the image at build time (see prod stage below).

RUN conda clean -afy && \
    rm -rf /root/.cache/pip /tmp/*

# =========================
# Stage 2: dev
# For development: source tree is bind-mounted at runtime.
# entrypoint.dev.sh handles ViTPose + DROID-SLAM on first boot.
# =========================
FROM builder-base AS dev

ENV PATH=/opt/conda/envs/slahmr/bin:/opt/conda/bin:$PATH
ENV CONDA_DEFAULT_ENV=slahmr
ENV PYTHONUNBUFFERED=1
ENV FORCE_CUDA=1

WORKDIR /workspace/slahmr

# entrypoint script is provided by the bind-mounted source tree;
# we also copy a host-side copy as fallback
COPY entrypoint.dev.sh /entrypoint.dev.sh
RUN chmod +x /entrypoint.dev.sh

ENTRYPOINT ["/entrypoint.dev.sh"]
CMD ["bash"]

# =========================
# Stage 3: prod
# For distribution/execution: Minimal runtime image.
# ViTPose and DROID-SLAM must be installed before build
# (run `make init` + full setup, then build prod target).
# =========================
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 AS prod

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      ffmpeg \
      git \
      libegl1 \
      libgl1 \
      libglib2.0-0 \
      libglu1-mesa \
      libgomp1 \
      libsm6 \
      libxext6 \
      libxrender1 \
      unzip \
      wget \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder-base /opt/conda /opt/conda
COPY --from=builder-base /workspace/slahmr /workspace/slahmr

ENV PATH=/opt/conda/envs/slahmr/bin:/opt/conda/bin:$PATH
ENV CONDA_DEFAULT_ENV=slahmr
ENV PYTHONUNBUFFERED=1
ENV FORCE_CUDA=1
ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.5;8.0;8.6;8.9;9.0+PTX"

COPY entrypoint.prod.sh /entrypoint.prod.sh
RUN chmod +x /entrypoint.prod.sh

WORKDIR /workspace/slahmr

ENTRYPOINT ["/entrypoint.prod.sh"]
CMD ["bash"]
