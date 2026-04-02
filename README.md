tigger04/make-audiobook is graet that it's x-platform but it relies on either piper or kokoro-tts which is on top of python and it's SLOW
I'm sitting here on M3 and M4 hardware that's not being taken advantage of

I'm ready to park make-audiobook and look into creating something new that's fully optimized for apple silicon - something fast that can do real time speech  (or faster if generating audiobooks) and that can be used in a variety of contexts - not just for making audiobooks but also for things like screen readers, voice assistants, etc.


---

initial cursory research dump:

It does both. The short answer: Kokoro is fast enough for real-time use, and several implementations explicitly support streaming.
Streaming/real-time options:

The CLI wrapper by nazdridoy supports a --stream flag that pipes audio directly to playback GitHub (e.g. echo "Hello" | kokoro-tts - --stream).
The Rust implementation (Kokoros) has an OpenAI-compatible HTTP server that supports streaming audio generation via "stream": true, with reported time-to-first-audio of 1–2 seconds. GitHub You can pipe it straight into ffplay for live playback.
There's a fastrtc integration pairing Kokoro with Moonshine STT for real-time voice chat Medium, which is about as real-time as it gets.

Why it works for real-time: The architecture generates speech in a single efficient pass without diffusion or autoregressive bottlenecks, which makes it fast enough for both real-time and batch use. Unreal Speech At 82M parameters it's small enough to run on modest hardware at interactive speeds.
Batch/pre-baked: It also handles long-form generation well, with EPUB/PDF ingestion, chapter splitting, and output to wav/mp3 files.
So for your poetry video pipeline, you could use it either way: pre-render audio files as you're doing now, or potentially stream TTS in a more interactive workflow. The Rust version would be worth a look if latency matters to you, given the CLI-first and FOSS angle.
One caveat from the official HuggingFace page: sites like kokorottsai.com and kokorotts.net are flagged by the maintainer as likely scams Hugging Face, so stick to the hexgrad GitHub/HuggingFace repos as canonical sources.link?6:19 PMThe main official sources:

GitHub: https://github.com/hexgrad/kokoro
HuggingFace model card: https://huggingface.co/hexgrad/Kokoro-82M
HuggingFace demo space: https://huggingface.co/spaces/hexgrad/Kokoro-TTS

And the community implementations I mentioned:

Rust version (Kokoros): https://github.com/lucasjinreal/Kokoros
CLI wrapper (Python): https://github.com/nazdridoy/kokoro-tts
fastrtc real-time voice chat tutorial: https://medium.com/@princekrampah/real-time-llm-voice-chat-in-python-kokoro-moonshine-open-source-models-6c6270cbe967
and how do they perform on apple silicon6:20 PMSearched the webSearched the webRuns well on Apple Silicon. Several paths, depending on what you want:
Native MLX (best for M-series):
mlx-audio is built specifically on Apple's MLX framework, optimised for Apple Silicon, with Kokoro as a supported model. GitHub This is probably the most natural fit for you. It supports streaming, quantization (down to 4-bit), and has an OpenAI-compatible REST API. CLI is straightforward:
bashpip install mlx-audio
mlx_audio.tts.generate --model mlx-community/Kokoro-82M-bf16 --text 'Hello!' --stream --lang_code a
There's also a Swift/MLX port (kokoro-ios) that generates audio roughly 3.3× faster than real-time on an iPhone 13 Pro GitHub, so on an M-series Mac it'll be quicker still.
ONNX Runtime:
kokoro-onnx focuses on running efficiently on commodity hardware including macOS with Apple Silicon, delivering near real-time performance. SourceForge This is the lighter-weight option if you don't want the MLX dependency chain.
PyTorch with MPS:
The official hexgrad repo notes you can set PYTORCH_ENABLE_MPS_FALLBACK=1 to enable GPU acceleration on M1/M2/M3/M4 devices. GitHub
Full local voice stack:
There's a tested architecture combining Whisper.cpp + Ollama + Kokoro ONNX on Apple Silicon that achieves sub-3-second turn latency after the first exchange, tested on an M3 Pro. DEV Community Total footprint around 500MB.
macOS apps:
Kokori is a native macOS menubar app wrapping Kokoro TTS with a local REST API, fully offline. Kokori And MimikaStudio reports sub-200ms latency for Kokoro TTS on Apple Silicon. GitHub
For your storyboard-gen pipeline, mlx-audio is probably the most interesting option: FOSS, CLI-friendly, native Metal acceleration, streaming support, and you could quantize the model to keep memory footprint minimal.
