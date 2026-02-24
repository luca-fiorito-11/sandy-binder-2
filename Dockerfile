# --- Base image containing OpenMC ---
FROM openmc/openmc:latest as base

# --- Stage 1: Build NJOY2016 ---
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    cmake \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Build NJOY
RUN git clone --depth 1 https://github.com/njoy/NJOY2016.git \
    && cd NJOY2016 && mkdir build && cd build \
    && cmake -DPython3_EXECUTABLE=$(which python3) .. \
    && make -j$(nproc) && make install


# --- Stage 2: Final Binder image ---
FROM openmc/openmc:latest

# Avoid writing .pyc files and enable unbuffered output
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install Python packages
RUN pip install --no-cache --upgrade pip && \
    pip install --no-cache \
        notebook \
        jupyterlab \
        matplotlib \
        seaborn \
        scikit-learn \
        serpentTools \
        sandy

# Create user for Binder
ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER ${NB_USER}
ENV HOME /home/${NB_USER}

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

WORKDIR ${HOME}
USER ${USER}

# Copy NJOY binary from builder stage
COPY --from=builder /usr/local/bin/njoy /usr/local/bin/
ENV NJOY=/usr/local/bin/njoy

# Copy local repository files into Binder home
COPY . ${HOME}

# Ensure permissions
RUN chown -R ${NB_UID}:${NB_UID} ${HOME}
