# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    ninja-build \
    aria2 \
    git-lfs \ 
    vim \
    build-essential \
    gcc \
    bash \
    ca-certificates \
    aria2 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel onnxruntime-gpu opencv-python requests triton

RUN uv pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# disable tracking
RUN comfy --workspace /comfyui tracking disable

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# from other download script installation parts

RUN cd /tmp/ && git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" && \
  mv CivitAI_Downloader/download_with_aria.py "/usr/local/bin/" && \
  chmod +x "/usr/local/bin/download_with_aria.py" && \
  rm -rf CivitAI_Downloader


ENV COMFYUI_DIR="/comfyui"
ENV WORKFLOW_DIR="/comfyui/user/default/workflows"
ENV CUSTOM_NODES_DIR="/comfyui/custom_nodes"

RUN for repo in \
    https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git \
    https://github.com/kijai/ComfyUI-KJNodes.git \
    https://github.com/rgthree/rgthree-comfy.git \
    https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git \
    https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git \
    https://github.com/Jordach/comfy-plasma.git \
    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    https://github.com/bash-j/mikey_nodes.git \
    https://github.com/ltdrdata/ComfyUI-Impact-Pack.git \
    https://github.com/Fannovel16/comfyui_controlnet_aux.git \
    https://github.com/yolain/ComfyUI-Easy-Use.git \
    https://github.com/kijai/ComfyUI-Florence2.git \
    https://github.com/ShmuelRonen/ComfyUI-LatentSyncWrapper.git \
    https://github.com/WASasquatch/was-node-suite-comfyui.git \
    https://github.com/theUpsider/ComfyUI-Logic.git \
    https://github.com/cubiq/ComfyUI_essentials.git \
    https://github.com/chrisgoringe/cg-image-picker.git \
    https://github.com/chflame163/ComfyUI_LayerStyle.git \
    https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git \
    https://github.com/Jonseed/ComfyUI-Detail-Daemon.git \
    https://github.com/shadowcz007/comfyui-mixlab-nodes.git \
    https://github.com/chrisgoringe/cg-use-everywhere.git \
    https://github.com/ClownsharkBatwing/RES4LYF \
    https://github.com/welltop-cn/ComfyUI-TeaCache.git \
    https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
    https://github.com/Jonseed/ComfyUI-Detail-Daemon.git \
    https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git \
    https://github.com/BadCafeCode/masquerade-nodes-comfyui.git \
    https://github.com/1038lab/ComfyUI-RMBG.git \
    https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
    https://github.com/bash-j/mikey_nodes.git \
    https://github.com/1038lab/ComfyUI-JoyCaption.git \
    https://github.com/sipie800/ComfyUI-PuLID-Flux-Enhanced.git \
    https://github.com/M1kep/ComfyLiterals.git; \
    do \
        cd /comfyui/custom_nodes; \
        repo_dir=$(basename "$repo" .git); \
        if [ "$repo" = "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git" ]; then \
            git clone --recursive "$repo"; \
        else \
            git clone "$repo"; \
        fi; \
        if [ -f "${CUSTOM_NODES_DIR}/$repo_dir/requirements.txt" ]; then \
            uv pip install -r "${CUSTOM_NODES_DIR}/$repo_dir/requirements.txt"; \
        fi; \
        if [ -f "${CUSTOM_NODES_DIR}/$repo_dir/install.py" ]; then \
            uv python3 "${CUSTOM_NODES_DIR}/$repo_dir/install.py"; \
        fi; \
    done

# sage attention
RUN cd /tmp/ && git clone https://github.com/thu-ml/SageAttention.git && \
  cd SageAttention && \
  uv python3 setup.py install && \
  cd .. && \
  rm -rf SageAttention

# clean pip cache


# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base AS downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG CIVITAI_TOKEN
ARG LORAS_IDS_TO_DOWNLOAD
ARG CHECKPOINT_IDS_TO_DOWNLOAD

ENV CIVITAI_TOKEN=${CIVITAI_TOKEN}
ENV HUGGINGFACE_ACCESS_TOKEN=${HUGGINGFACE_ACCESS_TOKEN}
ENV LORAS_IDS_TO_DOWNLOAD=${LORAS_IDS_TO_DOWNLOAD}
ENV CHECKPOINT_IDS_TO_DOWNLOAD=${CHECKPOINT_IDS_TO_DOWNLOAD}

# Set default model type if none is provided no spaces around commas
# has to be a guarded list ",listwithoutspace,"
ARG MODEL_TYPE=",sdxl,upscale_model,faceid,custom_chkpt_loras,"

# Change working directory to ComfyUI
WORKDIR /comfyui

ENV COMFYUI_DIR="/comfyui"
ENV WORKFLOW_DIR="/comfyui/user/default/workflows"
ENV CUSTOM_NODES_DIR="/comfyui/custom_nodes"

ENV DIFFUSION_MODELS_DIR="$COMFYUI_DIR/models/diffusion_models"
ENV CHECKPOINT_DIR="${COMFYUI_DIR}/models/checkpoints"
ENV TEXT_ENCODERS_DIR="$COMFYUI_DIR/models/text_encoders"
ENV CLIP_VISION_DIR="$COMFYUI_DIR/models/clip_vision"
ENV CLIP_DIR="${COMFYUI_DIR}/models/clip"
ENV VAE_DIR="$COMFYUI_DIR/models/vae"
ENV LORAS_DIR="$COMFYUI_DIR/models/loras"
ENV UNET_DIR="${COMFYUI_DIR}/models/unet"
ENV UPSCALE_MODELS_DIR="$COMFYUI_DIR/models/upscale_models"
ENV INSIGHTFACE_DIR="${COMFYUI_DIR}/models/insightface/models"
ENV PULID_DIR="${COMFYUI_DIR}/models/pulid"
ENV CONTROLNET_DIR="${COMFYUI_DIR}/models/controlnet"
ENV IPADAPTER_DIR="${COMFYUI_DIR}/models/ipadapter"


# Create necessary directories upfront
RUN mkdir -p ${DIFFUSION_MODELS_DIR} ${CHECKPOINT_DIR} ${TEXT_ENCODERS_DIR} \
  ${CLIP_VISION_DIR} ${CLIP_DIR} ${VAE_DIR} ${LORAS_DIR} ${UNET_DIR} ${UPSCALE_MODELS_DIR} \
  ${INSIGHTFACE_DIR} ${PULID_DIR} ${CONTROLNET_DIR} ${IPADAPTER_DIR}

COPY 4xLSDIR.pth /4xLSDIR.pth
COPY src/download_model.sh /download_model.sh
RUN chmod +x /download_model.sh

# Download checkpoints/vae/unet/clip models to include in image based on model type
RUN echo "$MODEL_TYPE" | grep -q ",sdxl," && \
      wget -q -O models/checkpoints/sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors && \
      wget -q -O models/vae/sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors && \
      wget -q -O models/vae/sdxl-vae-fp16-fix.safetensors https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors || true

RUN echo "$MODEL_TYPE" | grep -q ",sd3," && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/checkpoints/sd3_medium_incl_clips_t5xxlfp8.safetensors https://huggingface.co/stabilityai/stable-diffusion-3-medium/resolve/main/sd3_medium_incl_clips_t5xxlfp8.safetensors || true 

RUN echo "$MODEL_TYPE" | grep -q ",flux1-schnell," && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-schnell.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors && \
      wget -q -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors || true

RUN echo "$MODEL_TYPE" | grep -q ",flux1-dev," && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
      wget -q -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors || true

RUN echo "$MODEL_TYPE" | grep -q ",flux1-dev-fp8," && \
      wget -q -O models/checkpoints/flux1-dev-fp8.safetensors https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors || true

RUN echo "${MODEL_TYPE}" | grep -q ",pulid," && \
  /bin/bash /download_model.sh "https://huggingface.co/guozinan/PuLID/resolve/main/pulid_flux_v0.9.1.safetensors" "$PULID_DIR/pulid_flux_v0.9.1.safetensors"

RUN echo "${MODEL_TYPE}}" | grep -q ",faceid," && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors" "$IPADAPTER_DIR/ip-adapter-plus-face_sdxl_vit-h.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors" "$IPADAPTER_DIR/ip-adapter-plus_sdxl_vit-h.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors" "$IPADAPTER_DIR/ip-adapter_sdxl_vit-h.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$IPADAPTER_DIR/ip-adapter-faceid-plusv2_sdxl.bin" && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$CLIPVISION_DIR/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors" "$CLIPVISION_DIR/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" "$LORAS_DIR/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/24xx/segm/resolve/main/face_yolov8m-seg_60.pt" "$COMFYUI_DIR/models/ultralytics/segm/face_yolov8m-seg_60.pt"


RUN echo "$MODEL_TYPE" | grep -q ",wan21_480p," && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_480p_14B_bf16.safetensors"  && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_14B_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_1.3B_bf16.safetensors"

RUN echo "$MODEL_TYPE" | grep -q ",wan21_720p," && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_720p_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_720p_14B_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_14B_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_1.3B_bf16.safetensors"

RUN echo "$MODEL_TYPE" | grep -q ",vace," && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_1.3B_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_14B_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-VACE_module_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/Wan2_1-VACE_module_14B_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-VACE_module_1_3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/Wan2_1-VACE_module_1_3B_bf16.safetensors"

RUN echo "$MODEL_TYPE" | grep -q ",wan22," && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_t2v_high_noise_14B_fp16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_t2v_low_noise_14B_fp16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_high_noise_14B_fp16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_low_noise_14B_fp16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_ti2v_5B_fp16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan2.2_vae.safetensors" "$VAE_DIR/wan2.2_vae.safetensors"

# shared stuff for wan/vace
RUN echo "${MODEL_TYPE}" | grep -q "wan21|vace|wan22" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_CausVid_14B_T2V_lora_rank32.safetensors" "$LORAS_DIR/Wan21_CausVid_14B_T2V_lora_rank32.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" "$LORAS_DIR/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$TEXT_ENCODERS_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" "$TEXT_ENCODERS_DIR/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors" "$TEXT_ENCODERS_DIR/umt5-xxl-enc-bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "$CLIP_VISION_DIR/clip_vision_h.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" "$VAE_DIR/Wan2_1_VAE_bf16.safetensors" && \
  /bin/bash /download_model.sh "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$VAE_DIR/wan_2.1_vae.safetensors"
  
RUN echo "${MODEL_TYPE}" | grep -q ",upscale_model," && \
  mv "/4xLSDIR.pth" "${UPSCALE_MODELS_DIR}/4xLSDIR.pth" && \
  /bin/bash /download_model.sh "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pt" && \
  /bin/bash /download_model.sh "https://huggingface.co/RafaG/models-ESRGAN/resolve/82caaaedb2d27e9f76472351828178b62995c2f1/4xFaceUpLDAT.pth" "${UPSCALE_MODELS_DIR}/4xFaceUpLDAT.pth"

RUN echo "$MODEL_TYPE" | grep -q ",custom_chkpt_loras," && \
  declare -A MODEL_CATEGORIES=( \
      ["$COMFYUI_DIR/models/checkpoints"]="$CHECKPOINT_IDS_TO_DOWNLOAD" \
      ["$COMFYUI_DIR/models/loras"]="$LORAS_IDS_TO_DOWNLOAD" \
  ) ; \
  for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do \
    mkdir -p "$TARGET_DIR" ; \
    MODEL_IDS_STRING="${MODEL_CATEGORIES[$TARGET_DIR]}" ; \
    # Skip if the value is the default placeholder
    if [[ "x$MODEL_IDS_STRING" == x"" ]]; then \
        echo "⏭️  Skipping downloads for $TARGET_DIR (default value detected)" ; \
        continue ;\
    fi ;\
    IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING" ;\
    for MODEL_ID in "${MODEL_IDS[@]}"; do \
        sleep 1 ; \
        echo "🚀 Scheduling download: $MODEL_ID to $TARGET_DIR" ; \
        (cd "$TARGET_DIR" && download_with_aria.py -m "$MODEL_ID") ; \
    done ; \
  done 


# Stage 3: Final image
FROM base AS final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models
