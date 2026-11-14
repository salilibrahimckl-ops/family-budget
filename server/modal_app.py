"""Hosts the recitation teacher (app.py) on Modal, which bills per second and gives a
free monthly credit. The container sleeps when unused and wakes on the next request.

Deploy:  modal deploy modal_app.py   (done by .github/workflows/hifz-teacher.yml)
"""
from pathlib import Path

import modal

HERE = Path(__file__).parent
MODEL = "obadx/muaalem-model-v3_2"


def _download():
    from transformers import AutoFeatureExtractor
    from quran_muaalem.modeling.modeling_multi_level_ctc import Wav2Vec2BertForMultilevelCTC
    from quran_muaalem.modeling.multi_level_tokenizer import MultiLevelTokenizer

    AutoFeatureExtractor.from_pretrained(MODEL)
    MultiLevelTokenizer(MODEL)
    Wav2Vec2BertForMultilevelCTC.from_pretrained(MODEL)


image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "libsndfile1")
    .pip_install("torch>=2.7.0", "torchaudio>=2.7.0", index_url="https://download.pytorch.org/whl/cpu")
    .pip_install(
        "quran-muaalem>=0.3.0",
        "quran-transcript>=0.6.4",
        "transformers==4.55.2",
        "librosa>=0.11.0",
        "numba>=0.61.2",
        "fastapi>=0.116.1",
        "python-multipart>=0.0.20",
        "silero-vad>=5.1",
    )
    .run_function(_download)  # the model is baked into the image: quick wake-ups
    .add_local_dir(HERE, "/root/server", ignore=["test_*", "__pycache__", "Dockerfile", "README.md", "*.txt"])
)

app = modal.App("hifz-teacher")


@app.cls(
    image=image,
    cpu=8.0,
    memory=8192,
    timeout=900,
    scaledown_window=300,
    max_containers=1,  # streaming sessions must reach the same container
    enable_memory_snapshot=True,  # wake up with the model already in memory
)
@modal.concurrent(max_inputs=32)
class Teacher:
    @modal.enter(snap=True)
    def load(self):
        import sys

        sys.path.insert(0, "/root/server")
        import engine

        engine.M.load()
        from silero_vad import load_silero_vad

        load_silero_vad()  # warm the voice detector too

    @modal.enter(snap=False)
    def threads(self):
        import os

        import torch

        torch.set_num_threads(max(1, os.cpu_count() or 1))

    @modal.asgi_app()
    def web(self):
        import sys

        sys.path.insert(0, "/root/server")
        from app import app as fastapi_app

        return fastapi_app
