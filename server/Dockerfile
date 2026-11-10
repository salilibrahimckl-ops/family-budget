# Hugging Face Space (Docker SDK), free CPU hardware.
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libsndfile1 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user PATH=/home/user/.local/bin:$PATH HF_HOME=/home/user/.cache/huggingface
WORKDIR /home/user/app
COPY --chown=user requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt
# Download the model at build time so the first check after a restart is quick.
RUN python -c "from transformers import AutoFeatureExtractor; from quran_muaalem.modeling.modeling_multi_level_ctc import Wav2Vec2BertForMultilevelCTC as M; from quran_muaalem.modeling.multi_level_tokenizer import MultiLevelTokenizer as T; n='obadx/muaalem-model-v3_2'; AutoFeatureExtractor.from_pretrained(n); T(n); M.from_pretrained(n)"
COPY --chown=user . .
EXPOSE 7860
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
