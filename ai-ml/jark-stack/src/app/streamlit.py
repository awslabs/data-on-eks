import streamlit as st
import requests
from urllib.parse import urlencode
from PIL import Image
import tempfile


### Update Hostname before building image
base_url=""

st.title("Welcome to dogbooth! :dog:")
st.header("_a place to create images of [v]dog  in beautiful scenes._")


prompt = st.chat_input("a photo of a [v]dog ...")
if prompt:
    query_params = {
        "prompt": prompt
    }
    encoded_query = urlencode(query_params)
    image_url = f"{base_url}?{encoded_query}"

    with st.spinner("Wait for it..."):
        response = requests.get(image_url, timeout=180)

        if response.status_code == 200:
            content_size = len(response.content)
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                f.write(response.content)
            st.image(Image.open(f.name), caption=prompt)
            st.balloons()
        else:
            st.error(f"Failed to download image. Status code: {response.status_code}")
