# Dockerfile may have following Arguments:
# tag - tag for the Base image, (e.g. 2.9.1 for tensorflow)
# branch - user repository branch to clone (default: master, another option: test)
# jlab - if to insall JupyterLab (true) or not (false)
#
# To build the image:
# $ docker build -t <dockerhub_user>/<dockerhub_repo> --build-arg arg=value .
# or using default args:
# $ docker build -t <dockerhub_user>/<dockerhub_repo> .
#
# [!] Note: For the Jenkins CI/CD pipeline, input args are defined inside the
# Jenkinsfile, not here!

ARG tag=2.3.3

# Base image, e.g. tensorflow/tensorflow:2.9.1
FROM tensorflow/tensorflow:${tag}

LABEL maintainer='Jean-Marie BAUDET'
LABEL version='0.0.1'
# WIP : Identification of marine species from EMSO Azores deep-sea obervatory

# What user branch to clone [!]
ARG branch=master

# If to install JupyterLab
ARG jlab=true

# Outdate ubuntu1804 used by tensorflow 2.3.3 need a updated apt key to install cuda10.1
ARG tag
RUN if [[ ${tag} == *gpu* ]] ; \
then \
    rm -f /etc/apt/sources.list.d/nvidia-ml.list && \
    apt-key del 7fa2af80 && \
    apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/3bf863cc.pub  && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends \
        cuda-toolkit-10-1 ; \
fi

# Install Ubuntu packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        curl \
        nano \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*


# Create and activate python virtual env
RUN python3 -m venv --system-site-packages /srv/.py-venv

RUN echo ". /srv/.py-venv/bin/activate" > ~/.bashrc && \
    echo "PATH=/srv/.py-venv/bin/:$PATH" > ~/.profile

ENV PATH /srv/.py-venv/bin/:$PATH

# Update python packages
# [!] Remember: DEEP API V2 only works with python>=3.6
RUN python3 --version && \
    pip3 install --no-cache-dir --upgrade pip "setuptools<60.0.0" wheel

# TODO: remove setuptools version requirement when [1] is fixed
# [1]: https://github.com/pypa/setuptools/issues/3301

# Set LANG environment
ENV LANG C.UTF-8

# Set the working directory
WORKDIR /srv

# Install rclone (needed if syncing with NextCloud for training; otherwise remove)
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.deb && \
    dpkg -i rclone-current-linux-amd64.deb && \
    apt install -f && \
    mkdir /srv/.rclone/ && \
    touch /srv/.rclone/rclone.conf && \
    rm rclone-current-linux-amd64.deb && \
    rm -rf /var/lib/apt/lists/*

ENV RCLONE_CONFIG=/srv/.rclone/rclone.conf

# Install DEEPaaS from source until 2.1 release is made to PyPi
RUN pip3 install --no-cache-dir --upgrade deepaas==1.3.0

# Initialization scripts
RUN git clone https://github.com/deephdc/deep-start /srv/.deep-start && \
    ln -s /srv/.deep-start/deep-start.sh /usr/local/bin/deep-start && \
    ln -s /srv/.deep-start/run_jupyter.sh /usr/local/bin/run_jupyter

# Install JupyterLab
ENV JUPYTER_CONFIG_DIR /srv/.deep-start/
# Necessary for the Jupyter Lab terminal
ENV SHELL /bin/bash
RUN if [ "$jlab" = true ]; then \
       # by default has to work (1.2.0 wrongly required nodejs and npm)
       pip3 install --no-cache-dir jupyterlab ; \
    else echo "[INFO] Skip JupyterLab installation!"; fi

# Install user app
RUN git clone -b $branch https://github.com/jmbIFR/marine_species_seg && \
    cd  marine_species_seg && \
    pip3 install --no-cache-dir -e . && \
    cd ..

# Open ports: DEEPaaS (5000), Monitoring (6006), Jupyter (8888)
EXPOSE 5000 6006 8888

# Launch deepaas
CMD ["deepaas-run", "--listen-ip", "0.0.0.0", "--listen-port", "5000"]
