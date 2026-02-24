############################################
# Stage 1 — Build NJOY + OpenMC
############################################
FROM python:3.11-slim AS builder

# System dependencies required for compiling NJOY and OpenMC
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    cmake \
    git \
    curl \
    libhdf5-dev \
    hdf5-tools \
    && rm -rf /var/lib/apt/lists/*

# --- Build NJOY2016 ---
RUN git clone --depth 1 https://github.com/njoy/NJOY2016.git \
 && cd NJOY2016 \
 && mkdir build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release .. \
 && make -j$(nproc)

# --- Build OpenMC (minimal: no MPI) ---
# Official OpenMC instructions use: cmake, then make. [1](https://binderhub.readthedocs.io/en/latest/reference/app.html)
RUN git clone --depth 1 https://github.com/openmc-dev/openmc.git \
 && cd openmc \
 && mkdir build && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release \
          -DOPENMC_ENABLE_MPI=OFF \
          -DOPENMC_USE_OPENMP=ON \
          -DOPENMC_USE_DEFAULT_PATHS=ON \
          .. \
 && make -j$(nproc)

# Install Python OpenMC API from source (required for Python 3.11)
RUN cd openmc && pip install .


############################################
# Stage 2 — Runtime Binder Image
############################################
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install Python dependencies needed at runtime
RUN pip install --no-cache --upgrade pip && \
    pip install --no-cache \
        notebook \
        jupyterlab \
        sandy \
        serpentTools \
        seaborn \
        matplotlib \
        scikit-learn

############################################
# Create Binder user safely
############################################
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
# Install OpenMC runtime (binary + library + Python API)
############################################

# Copy OpenMC Python source tree & install API
COPY --from=builder /openmc /tmp/openmc_src
RUN pip install /tmp/openmc_src

# Binary
COPY --from=builder /openmc/build/bin/openmc /usr/local/bin/openmc

# Shared libraries (needed for the executable)
COPY --from=builder /openmc/build/lib /usr/local/lib
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

# Install NJOY binary
COPY --from=builder /NJOY2016/build/njoy /usr/local/bin/njoy
ENV NJOY=/usr/local/bin/njoy

############################################
# Copy repository content (Binder-safe)
############################################
WORKDIR /home/${NB_USER}
COPY --chown=${NB_UID}:${NB_UID} . /home/${NB_USER}

USER ${NB_USER}

############################################
# Binder: Start JupyterLab
############################################
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser"]
