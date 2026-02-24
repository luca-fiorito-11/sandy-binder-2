############################################
# Stage 1 — Build NJOY
############################################
FROM python:3.11-slim AS builder

# System deps
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    cmake \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Build NJOY2016
RUN git clone --depth 1 https://github.com/njoy/NJOY2016.git \
 && cd NJOY2016 && mkdir build && cd build \
 && cmake -DPython3_EXECUTABLE=$(which python3) .. \
 && make -j$(nproc) && make install


############################################
# Stage 2 — Final Binder image
############################################
FROM python:3.11-slim

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

############################################
# Create user (Binder-safe)
############################################
ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER=${NB_USER}
ENV HOME=/home/${NB_USER}

# Idempotent user creation (works on Binder & local Docker)
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
# Copy NJOY from builder
############################################
COPY --from=builder /usr/local/bin/njoy /usr/local/bin/
ENV NJOY=/usr/local/bin/njoy

############################################
# Copy project (BINDER-SAFE)
############################################
WORKDIR /home/${NB_USER}

# Copy files without .git (requires .dockerignore)
COPY --chown=${NB_UID}:${NB_UID} . /home/${NB_USER}

USER ${NB_USER}

############################################
# CMD — CRITICAL FOR BINDER
############################################
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser"]
