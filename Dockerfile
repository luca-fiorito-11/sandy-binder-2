############################################
# Stage 1 — Build NJOY + OpenMC
############################################
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    cmake \
    git \
    curl \
    hdf5-tools \
    libhdf5-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Build NJOY2016 ---
RUN git clone --depth 1 https://github.com/njoy/NJOY2016.git \
 && cd NJOY2016 && mkdir build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release .. \
 && make -j$(nproc)

# --- Build OpenMC (minimal, no MPI) ---
RUN git clone --depth 1 https://github.com/openmc-dev/openmc.git \
 && cd openmc \
 && mkdir build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release \
          -DOPENMC_ENABLE_MPI=OFF \
          -DOPENMC_USE_OPENMP=ON \
          -DOPENMC_USE_DEFAULT_PATHS=ON \
          .. \
 && make -j$(nproc)


############################################
# Stage 2 — Runtime (Binder)
############################################
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install Python dependencies (minimal)
RUN pip install --no-cache --upgrade pip && \
    pip install --no-cache \
        notebook \
        jupyterlab \
        sandy \
        serpentTools \
        seaborn \
        matplotlib \
        scikit-learn \
        openmc

# Create user
ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER=${NB_USER}
ENV HOME=/home/${NB_USER}

RUN if id -u "${NB_USER}" >/dev/null 2>&1; then \
        echo "User exists"; \
    else \
        if getent passwd "${NB_UID}" >/dev/null 2>&1; then \
            adduser --disabled-password --gecos "" "${NB_USER}"; \
        else \
            adduser --disabled-password --gecos "" --uid "${NB_UID}" "${NB_USER}"; \
        fi; \
    fi && \
    mkdir -p "${HOME}"

############################################
# Copy binaries from builder
############################################
# OpenMC executable
COPY --from=builder /openmc/build/bin/openmc /usr/local/bin/openmc
ENV OPENMC_CROSS_SECTIONS=""  # user will set or provide data

# NJOY
COPY --from=builder /NJOY2016/build/njoy /usr/local/bin/njoy
ENV NJOY=/usr/local/bin/njoy

############################################
# Copy repo content
############################################
WORKDIR /home/${NB_USER}
COPY --chown=${NB_UID}:${NB_UID} . /home/${NB_USER}

USER ${NB_USER}

############################################
# Binder entrypoint
############################################
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser"]
