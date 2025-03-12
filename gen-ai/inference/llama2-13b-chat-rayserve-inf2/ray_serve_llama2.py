import os
import logging
from fastapi import FastAPI
from ray import serve
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, GenerationConfig
from transformers_neuronx.llama.model import LlamaForSampling
from transformers_neuronx.module import save_pretrained_split

app = FastAPI()

llm_model_split = "llama-2-13b-chat-hf-split"
neuron_cores = int(os.getenv('NEURON_CORES', 24))  # Read from environment variable, default to 24

# --- Logging Setup ---
logger = logging.getLogger("ray.serve")
logger.setLevel(logging.INFO)
logging.basicConfig(level=logging.INFO)


# Define the APIIngress class responsible for handling inference requests
@serve.deployment(num_replicas=1)
@serve.ingress(app)
class APIIngress:
    def __init__(self, llama_model_handle):
        self.handle = llama_model_handle

    @app.get("/infer")
    async def infer(self, sentence: str):
        # Asynchronously perform inference using the provided sentence
        result = await self.handle.infer.remote(sentence)
        return result


# Define the LlamaModel class responsible for managing the Llama language model
@serve.deployment(
    name="Llama-2-13b-chat-hf",
    autoscaling_config={"min_replicas": 1, "max_replicas": 2},
    ray_actor_options={
        "resources": {"neuron_cores": neuron_cores},
        "runtime_env": {"env_vars": {"NEURON_CC_FLAGS": "-O1"}},
    },
)
class LlamaModel:
    def __init__(self):
        from transformers_neuronx.llama.model import LlamaForSampling
        from transformers_neuronx.module import save_pretrained_split

        llm_model = os.getenv('MODEL_ID', 'NousResearch/Llama-2-13b-chat-hf')
        logger.info(f"Using model ID: {llm_model}")

        # Check if the model split exists locally, and if not, download it
        if not os.path.exists(llm_model_split):
            logger.info(f"Saving model split for {llm_model} to local path {llm_model_split}")
            try:
                self.model = AutoModelForCausalLM.from_pretrained(llm_model)
                # Set and validate generation config
                generation_config = GenerationConfig(
                    do_sample=True,
                    temperature=0.9,
                    top_p=0.6,
                    top_k=50,
                )
                generation_config.validate()
                self.model.generation_config = generation_config
                save_pretrained_split(self.model, llm_model_split)
            except Exception as e:
                logger.error(f"Error during model download or split saving: {e}")
                raise e
        else:
            logger.info(f"Using existing model split {llm_model_split}")

        logger.info(f"Loading and compiling model {llm_model_split} for Neuron")
        try:
            self.neuron_model = LlamaForSampling.from_pretrained(
                llm_model_split, batch_size=1, tp_degree=neuron_cores, amp='f16'
            )
            self.neuron_model.to_neuron()
            logger.info("Model loaded and compiled successfully")
        except Exception as e:
            logger.error(f"Error during model loading or compilation: {e}")
            raise e

        self.tokenizer = AutoTokenizer.from_pretrained(llm_model)

    def infer(self, sentence: str):
        input_ids = self.tokenizer.encode(sentence, return_tensors="pt")
        with torch.inference_mode():
            try:
                logger.info(f"Performing inference on input: {sentence}")
                generated_sequences = self.neuron_model.sample(
                    input_ids, sequence_length=2048, top_k=50
                )
                decoded_sequences = [self.tokenizer.decode(seq, skip_special_tokens=True) for seq in generated_sequences]
                logger.info(f"Inference result: {decoded_sequences}")
                return decoded_sequences
            except Exception as e:
                logger.error(f"Error during inference: {e}")
                return {"error": "Inference failed"}


# Create an entry point for the FastAPI application
entrypoint = APIIngress.bind(LlamaModel.bind())
