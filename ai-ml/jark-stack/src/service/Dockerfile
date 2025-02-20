FROM rayproject/ray-ml:2.6.0-gpu

RUN pip install -U \
    git+https://github.com/huggingface/transformers diffusers

WORKDIR /serve_app

COPY dogbooth.py /serve_app/dogbooth.py
