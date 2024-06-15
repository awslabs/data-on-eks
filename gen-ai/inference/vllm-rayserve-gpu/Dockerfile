# https://hub.docker.com/layers/rayproject/ray/2.11.0-py310/images/sha256-de798e487b76a8f2412c718c43c5f342b3eb05e0705a71325102904cd27c3613?context=explore
FROM rayproject/ray:2.24.0-py310-cu118

# Maintainer label
LABEL maintainer="DoEKS"

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=non-interactive

# Install vLLM and other dependencies
RUN pip install vllm==0.4.3

WORKDIR /app

# Copy the serving script into the container
COPY vllm_serve.py /app/vllm_serve.py

# Expose the port for Ray Serve
EXPOSE 8000

# Set LD_LIBRARY_PATH to include the directory with libpython3.10.so.1.0
ENV LD_LIBRARY_PATH /home/ray/anaconda3/lib:$LD_LIBRARY_PATH

# Command to start the Ray Serve script
ENTRYPOINT ["python", "vllm_serve.py"]
