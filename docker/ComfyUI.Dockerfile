ARG CUDA_VERSION=12.1.1
ARG UBUNTU_VERSION=22.04
ARG BASE_IMAGE=nvidia/cuda:${CUDA_VERSION}-cudnn8-runtime-ubuntu${UBUNTU_VERSION}

FROM ${BASE_IMAGE} AS base

ARG COMFYUI_REPO=https://github.com/comfyanonymous/ComfyUI.git
ARG COMFYUI_REF=master
ARG GIT_SHA=dev

LABEL org.opencontainers.image.source="https://github.com/jjziets/ai-vibe-movie-maker" \
      org.opencontainers.image.revision="${GIT_SHA}"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    COMFY_USER=comfy \
    COMFY_HOME=/opt/ComfyUI \
    WRAPPER_HOME=/opt/framepack_wrapper \
    HF_HOME=/opt/.cache/huggingface \
    CUDA_VISIBLE_DEVICES=0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip git ffmpeg wget curl unzip jq aria2 \
      libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 tini gosu build-essential && \
    rm -rf /var/lib/apt/lists/*

# Create runtime user
RUN useradd --create-home --shell /bin/bash ${COMFY_USER}

# Clone ComfyUI
RUN git clone --depth=1 --branch ${COMFYUI_REF} ${COMFYUI_REPO} ${COMFY_HOME}

# Python environment + requirements
RUN python3 -m venv ${VIRTUAL_ENV} && \
    pip install --upgrade pip setuptools wheel && \
    pip install -r ${COMFY_HOME}/requirements.txt && \
    pip install fastapi uvicorn[standard] httpx pydantic-settings python-multipart huggingface_hub

# Install required custom nodes (FramePack wrapper + dependencies)
RUN mkdir -p ${COMFY_HOME}/custom_nodes && \
    git clone --depth=1 https://github.com/kijai/ComfyUI-FramePackWrapper ${COMFY_HOME}/custom_nodes/ComfyUI-FramePackWrapper && \
    pip install --no-cache-dir -r ${COMFY_HOME}/custom_nodes/ComfyUI-FramePackWrapper/requirements.txt && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Impact-Pack ${COMFY_HOME}/custom_nodes/ComfyUI-Impact-Pack && \
    pip install --no-cache-dir -r ${COMFY_HOME}/custom_nodes/ComfyUI-Impact-Pack/requirements.txt && \
    git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite ${COMFY_HOME}/custom_nodes/ComfyUI-VideoHelperSuite && \
    pip install --no-cache-dir -r ${COMFY_HOME}/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt

# Copy wrapper source
COPY src/framepack_wrapper ${WRAPPER_HOME}

# Example workflows / entrpoint assets
COPY comfyui_workflows/ ${COMFY_HOME}/user/default/workflows/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PYTHONPATH=${WRAPPER_HOME}:$PYTHONPATH \
    COMFYUI_PORT=9090 \
    COMFYUI_HOST=0.0.0.0 \
    WRAPPER_PORT=9443 \
    WRAPPER_HOST=0.0.0.0

WORKDIR ${COMFY_HOME}

EXPOSE 9090 9443

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]

