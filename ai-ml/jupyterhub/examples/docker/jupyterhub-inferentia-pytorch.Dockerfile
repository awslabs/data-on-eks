FROM 763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-inference-neuronx:1.13.1-neuronx-py310-sdk2.13.2-ubuntu20.04
LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"

RUN pip3 install \
    'jupyterhub==4.0.1' \
    'notebook'

# create a user, since we don't want to run as root
RUN useradd -m jovyan
ENV HOME=/home/jovyan
WORKDIR $HOME
USER jovyan

ENTRYPOINT ["jupyterhub-singleuser"]

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
# ARG NB_USER="jovyan"
# ARG NB_UID="1001"
# ARG NB_GID="101"

# SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# USER root

# ENV DEBIAN_FRONTEND noninteractive
# RUN apt-get update --yes && \
#     # - apt-get upgrade is run to patch known vulnerabilities in apt-get packages as
#     #   the ubuntu base image is rebuilt too seldom sometimes (less than once a month)
#     apt-get upgrade --yes && \
#     apt-get install --yes --no-install-recommends \
#     # - bzip2 is necessary to extract the micromamba executable.
#     bzip2 \
#     ca-certificates \
#     locales \
#     sudo \
#     # - tini is installed as a helpful container entrypoint that reaps zombie
#     #   processes and such of the actual executable we want to start, see
#     #   https://github.com/krallin/tini#why-tini for details.
#     tini \
#     wget && \
#     apt-get clean && rm -rf /var/lib/apt/lists/* && \
#     echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
#     locale-gen

# # Install all OS dependencies for Server that starts but lacks all
# # features (e.g., download as all possible file formats)
# RUN apt-get update --yes && \
#     apt-get install --yes --no-install-recommends \
#     fonts-liberation \
#     # - pandoc is used to convert notebooks to html files
#     #   it's not present in aarch64 ubuntu image, so we install it here
#     pandoc \
#     # - run-one - a wrapper script that runs no more
#     #   than one unique  instance  of  some  command with a unique set of arguments,
#     #   we use `run-one-constantly` to support `RESTARTABLE` option
#     run-one && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*

# # Configure environment
# ENV CONDA_DIR=/opt/conda \
#     SHELL=/bin/bash \
#     NB_USER="${NB_USER}" \
#     NB_UID=${NB_UID} \
#     NB_GID=${NB_GID} \
#     LC_ALL=en_US.UTF-8 \
#     LANG=en_US.UTF-8 \
#     LANGUAGE=en_US.UTF-8
# ENV PATH="${CONDA_DIR}/bin:${PATH}" \
#     HOME="/home/${NB_USER}"

# # Copy a script that we will use to correct permissions after running certain commands
# COPY docker/fix-permissions /usr/local/bin/fix-permissions
# RUN chmod a+rx /usr/local/bin/fix-permissions

# # Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# # hadolint ignore=SC2016
# RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
#    # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
#    echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc

# # Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# # and make sure these dirs are writable by the `users` group.
# RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
#     sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
#     sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
#     useradd --no-log-init --create-home --shell /bin/bash --uid "${NB_UID}" --no-user-group "${NB_USER}" && \
#     mkdir -p "${CONDA_DIR}" && \
#     chown "${NB_USER}:${NB_GID}" "${CONDA_DIR}" && \
#     chmod g+w /etc/passwd && \
#     fix-permissions "${CONDA_DIR}" && \
#     fix-permissions "/home/${NB_USER}"

# USER ${NB_UID}
# ARG PYTHON_VERSION=3.10

# RUN mkdir "/home/${NB_USER}/work" && \
#     fix-permissions "/home/${NB_USER}"

# # Download and install Micromamba, and initialize Conda prefix.
# #   <https://github.com/mamba-org/mamba#micromamba>
# #   Similar projects using Micromamba:
# #     - Micromamba-Docker: <https://github.com/mamba-org/micromamba-docker>
# #     - repo2docker: <https://github.com/jupyterhub/repo2docker>
# # Install Python, Mamba and jupyter_core
# # Cleanup temporary files and remove Micromamba
# # Correct permissions
# # Do all this in a single RUN command to avoid duplicating all of the
# # files across image layers when the permissions change
# COPY --chown="${NB_UID}:${NB_GID}" docker/initial-condarc "${CONDA_DIR}/.condarc"
# WORKDIR /tmp
# RUN set -x && \
#     arch=$(uname -m) && \
#     if [ "${arch}" = "x86_64" ]; then \
#         # Should be simpler, see <https://github.com/mamba-org/mamba/issues/1437>
#         arch="64"; \
#     fi && \
#     wget --progress=dot:giga -O /tmp/micromamba.tar.bz2 \
#         "https://micromamba.snakepit.net/api/micromamba/linux-${arch}/latest" && \
#     tar -xvjf /tmp/micromamba.tar.bz2 --strip-components=1 bin/micromamba && \
#     rm /tmp/micromamba.tar.bz2 && \
#     PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
#     if [[ "${PYTHON_VERSION}" == "default" ]]; then PYTHON_SPECIFIER="python"; fi && \
#     # Install the packages
#     ./micromamba install \
#         --root-prefix="${CONDA_DIR}" \
#         --prefix="${CONDA_DIR}" \
#         --yes \
#         "${PYTHON_SPECIFIER}" \
#         'mamba' \
#         'jupyter_core' && \
#     rm micromamba && \
#     # Pin major.minor version of python
#     mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
#     mamba clean --all -f -y && \
#     fix-permissions "${CONDA_DIR}" && \
#     fix-permissions "/home/${NB_USER}"

# # Copy local files as late as possible to avoid cache busting
# COPY docker/run-hooks.sh docker/start.sh /usr/local/bin/

# USER root

# # Create dirs for startup hooks
# RUN mkdir /usr/local/bin/start-notebook.d && \
#     mkdir /usr/local/bin/before-notebook.d


# WORKDIR "${HOME}"

# USER ${NB_UID}

# # Install JupyterLab, Jupyter Notebook, JupyterHub and NBClassic
# # Generate a Jupyter Server config
# # Cleanup temporary files
# # Correct permissions
# # Do all this in a single RUN command to avoid duplicating all of the
# # files across image layers when the permissions change
# WORKDIR /tmp
# RUN mamba install --yes \
#     'jupyterlab' \
#     'notebook' \
#     'jupyterhub' \
#     'nbclassic' && \
#     jupyter server --generate-config && \
#     mamba clean --all -f -y && \
#     npm cache clean --force && \
#     jupyter lab clean && \
#     rm -rf "/home/${NB_USER}/.cache/yarn" && \
#     fix-permissions "${CONDA_DIR}" && \
#     fix-permissions "/home/${NB_USER}"

# ENV JUPYTER_PORT=8888
# EXPOSE $JUPYTER_PORT

# # Configure container startup
# CMD ["start-notebook.sh"]
# # Configure container startup
# ENTRYPOINT ["tini", "-g", "--"]

# # Copy local files as late as possible to avoid cache busting
# COPY docker/start-notebook.sh docker/start-singleuser.sh /usr/local/bin/
# COPY docker/jupyter_server_config.py docker/docker_healthcheck.py /etc/jupyter/

# # Fix permissions on /etc/jupyter as root
# USER root
# RUN fix-permissions /etc/jupyter/

# # HEALTHCHECK documentation: https://docs.docker.com/engine/reference/builder/#healthcheck
# # This healtcheck works well for `lab`, `notebook`, `nbclassic`, `server` and `retro` jupyter commands
# # https://github.com/jupyter/docker-stacks/issues/915#issuecomment-1068528799
# HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
#     CMD /etc/jupyter/docker_healthcheck.py || exit 1

# # Switch back to jovyan to avoid accidental container runs as root
# USER ${NB_UID}

# WORKDIR "${HOME}"