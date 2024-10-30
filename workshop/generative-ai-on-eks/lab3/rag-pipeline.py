# Ingest the data
from llama_index.core import SimpleDirectoryReader, VectorStoreIndex
import os.path
import urllib.request

file_url = "https://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0.s3.us-west-2.amazonaws.com/26c6c1a1-195e-4b01-847f-69c857425161/labs/skywing.pdf"
file_name = "skywing.pdf"
file_directory = "./data"
file_path = f"{file_directory}/{file_name}"

if not os.path.isfile(file_path):
    if not os.path.isdir(file_directory):
        os.mkdir(file_directory)
    urllib.request.urlretrieve(file_url, file_path)

documents = SimpleDirectoryReader(file_directory).load_data() # read the files in the data directory

# print(documents) # print the contents of the files

# Index the data
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.core import Settings

Settings.embed_model = HuggingFaceEmbedding(
    model_name="BAAI/bge-small-en-v1.5"
) # load an embedding model from HuggingFace instead of OpenAI

index = VectorStoreIndex.from_documents(documents, show_progress=True) # index the documents we loaded

# print(len(index.docstore.docs)) # print the length of the index

from llama_index.llms.openai_like import OpenAILike
from llama_index.core.base.llms.types import ChatMessage
from llama_index.core.memory import ChatMemoryBuffer

request = "What planes does SkyWing operate?"

message = [ChatMessage(content=request, role="user")] # creating a properly formatted message 
llm = OpenAILike(model="/data/model/neuron-mistral7bv0.3", api_base="http://vllm-mistral-inf2-head-svc:8000/v1", api_key="dummy", is_chat_model=True, context_window=1000) # load a custom LLM
response = llm.chat(message) # send our question to the LLM without our index
print("\n\n")
print(response) # you'll note that the LLM does not know about this new airline, SkyWing
print("\n\n")
memory = ChatMemoryBuffer.from_defaults(token_limit=1500) # Set the memory limit
query_engine = index.as_chat_engine(chat_mode="context",llm=llm, memory=memory, system_prompt=("you are a helpful question answering assistant")) # create a chat engine from our index and use our custom LLM
response = query_engine.chat(request) # send our question to the LLM with our index
print(response) # you'll note that the LLM now knows about SkyWing due to the provided index


