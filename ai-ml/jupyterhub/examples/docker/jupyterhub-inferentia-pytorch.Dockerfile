# TBD: Create image installing pytorch neuron packages - https://awsdocs-neuron.readthedocs-hosted.com/en/latest/general/setup/neuron-setup/pytorch/neuronx/ubuntu/torch-neuronx-ubuntu22.html#setup-torch-neuronx-ubuntu22
FROM jupyter/datascience-notebook:python-3.10.10

RUN pip3 install \
    'jupyterhub==4.0.1' \
    'notebook'

# create a user, since we don't want to run as root
RUN useradd -m jovyan
ENV HOME=/home/jovyan
WORKDIR $HOME
USER jovyan

ENTRYPOINT ["jupyterhub-singleuser"]