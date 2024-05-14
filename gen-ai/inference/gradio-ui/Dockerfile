# Use Python base image
FROM --platform=linux/amd64 python:3.12-slim

# Pass the gradio-app.py file
ARG GRADIO_APP

# Set working directory in the container
WORKDIR /app

# Copy the Python script into the container
COPY ${GRADIO_APP} /app/gradio-app.py

RUN pip install --no-cache-dir gradio requests Pillow

# Command to run the Python script
ENTRYPOINT ["python", "gradio-app.py"]
