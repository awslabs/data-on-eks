# pip install openai
# python3 openai-client.py

import os
from openai import OpenAI

# Set up the client
client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="dummy-key"  # The key doesn't matter for our custom server, but is required by the SDK
)

def chat_completion_example(messages, model="NousResearch/Meta-Llama-3-8B-Instruct", temperature=0.7, max_tokens=100):
    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens
        )
        return response
    except Exception as e:
        print(f"An error occurred: {e}")
        return None

def streaming_chat_completion_example(messages, model="NousResearch/Meta-Llama-3-8B-Instruct", temperature=0.7, max_tokens=100):
    try:
        stream = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
            stream=True
        )
        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                print(chunk.choices[0].delta.content, end="", flush=True)
        print()  # New line after streaming is complete
    except Exception as e:
        print(f"An error occurred: {e}")

# Example usage
if __name__ == "__main__":
    # Example 1: Simple chat completion
    messages = [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is the capital of India?"}
    ]

    print("Example 1 - Simple chat completion:")
    response = chat_completion_example(messages)
    if response:
        print(response.choices[0].message.content)
    print("\n")

    # Example 2: Chat completion with different parameters
    messages = [
        {"role": "system", "content": "You are a creative writing assistant."},
        {"role": "user", "content": "Write a short story about the starwars franchise"}
    ]

    print("Example 2 - Chat completion with different parameters:")
    response = chat_completion_example(messages, temperature=0.9, max_tokens=200)
    if response:
        print(response.choices[0].message.content)
    print("\n")

    # Example 3: Streaming chat completion
    messages = [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Count from 1 to 10, with a brief pause between each number."}
    ]

    print("Example 3 - Streaming chat completion:")
    streaming_chat_completion_example(messages)
