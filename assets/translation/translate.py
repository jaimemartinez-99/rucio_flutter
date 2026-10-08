import json
import os
import re
import sys

import ctranslate2
import sentencepiece


def translate(text, model_path):
    tokenizer = sentencepiece.SentencePieceProcessor(
        model_file=os.path.join(model_path, "sentencepiece.model")
    )
    translator = ctranslate2.Translator(
        os.path.join(model_path, "model"),
        device="cpu",
        compute_type="int8",
        inter_threads=1,
        intra_threads=max(1, min(4, os.cpu_count() or 1)),
    )
    paragraphs = text.split("\n")
    translated = []
    for paragraph in paragraphs:
        if not paragraph.strip():
            translated.append("")
            continue
        batches = []
        for sentence in re.split(r"(?<=[.!?])\s+", paragraph.strip()):
            tokens = tokenizer.encode(sentence, out_type=str)
            batches.extend(tokens[start : start + 256] for start in range(0, len(tokens), 256))
        results = translator.translate_batch(
            batches,
            beam_size=4,
            max_batch_size=16,
            max_input_length=0,
            max_decoding_length=512,
        )
        translated.append(" ".join(tokenizer.decode(result.hypotheses[0]) for result in results))
    return "\n".join(translated).strip()


if __name__ == "__main__":
    request = json.load(sys.stdin)
    result = translate(request["text"], sys.argv[1])
    print(json.dumps({"translation": result}, ensure_ascii=False))
