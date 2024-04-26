# Use Python base image
FROM --platform=linux/amd64 python:3.9-slim

# Set working directory in the container
WORKDIR /app

# Copy the Python script into the container
COPY gradio-app.py /app/gradio-app.py

RUN pip install --no-cache-dir gradio requests Pillow

# Command to run the Python script
ENTRYPOINT ["python", "gradio-app.py"]
