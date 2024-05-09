# Pass the gradio-app.py file
ARG GRADIO_APP

# Use Python base image
FROM --platform=linux/amd64 python:3.12-slim

# Set working directory in the container
WORKDIR /app

# Copy the Python script into the container
COPY ${GRADIO_APP} /app/${GRADIO_APP}

RUN pip install --no-cache-dir gradio requests Pillow

# Command to run the Python script
ENTRYPOINT ["python", "${GRADIO_APP}"]
