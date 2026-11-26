"""
Compare fish classifiers on public images in an isolated CI runner.
"""

import hashlib
import json
import os
import resource
import statistics
import sys
import time
import urllib.request
import zipfile

from pathlib import Path

os.environ["OMP_NUM_THREADS"] = "2"
os.environ["MKL_NUM_THREADS"] = "2"

CANDIDATES = [
    "Esox lucius", "Cyprinus carpio", "Anguilla anguilla", "Perca fluviatilis", "Rutilus rutilus",
    "Tinca tinca", "Abramis brama", "Salmo trutta", "Scardinius erythrophthalmus", "Silurus glanis",
    "Ctenopharyngodon idella", "Carassius carassius", "Carassius gibelio", "Leuciscus leuciscus",
    "Squalius cephalus", "Barbus barbus", "Alburnus alburnus", "Blicca bjoerkna", "Gymnocephalus cernua",
    "Sander lucioperca", "Gasterosteus aculeatus", "Salmo salar", "Oncorhynchus mykiss", "Thymallus thymallus",
    "Salvelinus fontinalis", "Salvelinus alpinus", "Coregonus lavaretus", "Gadus morhua", "Dicentrarchus labrax",
    "Platichthys flesus", "Scophthalmus maximus", "Scomber scombrus", "Pollachius pollachius", "Pollachius virens",
    "Lophius piscatorius", "Conger conger", "Scyliorhinus canicula", "Galeus melastomus", "Lepomis gibbosus",
    "Ameiurus melas", "Acipenser baerii", "Hucho hucho", "Misgurnus fossilis", "Cobitis taenia", "Phoxinus phoxinus",
]


def peak_mib() -> float:
    """
    Return the process peak resident memory on the Linux runner.
    """
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024


def public_photos() -> list[tuple[str, Path]]:
    """
    Download public guide images without accessing user data.
    """
    items = json.loads(Path("evaluation/public-fish.json").read_text())
    directory = Path(os.environ["RUNNER_TEMP"]) / "fish-public-evaluation"
    directory.mkdir(exist_ok=True)
    results = []
    for item in items:
        path = directory / (item["species"].replace(" ", "_") + ".jpg")
        request = urllib.request.Request(item["url"], headers={"User-Agent": "FishOnModelEvaluation/1.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            path.write_bytes(response.read())
        results.append((item["species"], path))
    return results


def report(model: str, rows: list[dict[str, object]], start: float) -> None:
    """
    Print per-photo predictions and a clearly qualified summary.
    """
    for row in rows:
        print(json.dumps(row), flush=True)
    summary = {
        "model": model,
        "photos": len(rows),
        "top1": sum(bool(row["top1"]) for row in rows),
        "top5": sum(bool(row["top5"]) for row in rows),
        "median_inference_seconds": round(statistics.median(float(row["seconds"]) for row in rows), 3),
        "peak_process_mib": round(peak_mib(), 1),
        "total_seconds": round(time.perf_counter() - start, 1),
        "caveat": "Ten convenience images, no verified training separation, whole images, not an accuracy estimate.",
    }
    print("SUMMARY " + json.dumps(summary), flush=True)


def bioclip() -> None:
    """
    Run BioCLIP 2 zero-shot using a disclosed set of UK fish candidates.
    """
    import open_clip
    import torch

    from PIL import Image, ImageOps

    start = time.perf_counter()
    torch.set_num_threads(2)
    model, _, preprocess = open_clip.create_model_and_transforms("hf-hub:imageomics/bioclip-2")
    model.eval()
    tokenizer = open_clip.get_tokenizer("hf-hub:imageomics/bioclip-2")
    texts = tokenizer([f"a photograph of a fish, {name}" for name in CANDIDATES])
    with torch.inference_mode():
        text = model.encode_text(texts)
        text = torch.nn.functional.normalize(text, dim=-1)
    print(json.dumps({"model": "BioCLIP 2", "candidate_count": len(CANDIDATES), "candidates": CANDIDATES, "loaded_peak_mib": round(peak_mib(), 1)}), flush=True)
    rows = []
    for expected, path in public_photos():
        with Image.open(path) as image:
            image = ImageOps.exif_transpose(image).convert("RGB")
            tensor = preprocess(image).unsqueeze(0)
        begin = time.perf_counter()
        with torch.inference_mode():
            features = torch.nn.functional.normalize(model.encode_image(tensor), dim=-1)
            indices = (features @ text.T)[0].topk(5).indices.tolist()
        names = [CANDIDATES[index] for index in indices]
        rows.append({"expected": expected, "predictions": names, "top1": names[0].casefold() == expected, "top5": expected in [name.casefold() for name in names], "seconds": round(time.perf_counter()-begin, 3)})
    report("BioCLIP 2; 45 supplied candidates", rows, start)


def fishial() -> None:
    """
    Run the official Fishial v0.10.2 checkpoint in a separate process.
    """
    import numpy as np
    import torch

    from PIL import Image, ImageOps

    start = time.perf_counter()
    torch.set_num_threads(2)
    model_path = Path(os.environ["RUNNER_TEMP"]) / "fishial-v0.10.2.zip"
    request = urllib.request.Request("https://storage.googleapis.com/fishial-ml-resources/classification_model_v0.10.2.zip", headers={"User-Agent": "FishOnModelEvaluation/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, model_path.open("wb") as dest:
        while chunk := response.read(1024 * 1024):
            dest.write(chunk)
    digest = hashlib.file_digest(model_path.open("rb"), "sha256").hexdigest()
    if digest != "a31d78a7021d7b8a94c87b816b6a7b49ba1b1ef0b7284942b8e3d522322ae078":
        raise ValueError("Unexpected Fishial archive checksum")
    with zipfile.ZipFile(model_path) as archive:
        archive.extract("model.pt", path=Path(os.environ["RUNNER_TEMP"]))
    model = torch.jit.load(str(Path(os.environ["RUNNER_TEMP"]) / "model.pt"), map_location="cpu").eval()
    labels = json.loads(bytes(model.class_mapping_json_bytes.cpu().tolist()).decode())
    centroids = model.natural_centroids.float()
    classes = model.natural_labels.long().unsqueeze(0)
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    print(json.dumps({"model":"Fishial 0.10.2", "candidate_count":len(labels), "loaded_peak_mib":round(peak_mib(), 1)}), flush=True)
    name_to_index = {value["label"].casefold(): int(index) for index, value in labels.items()}
    matched = [name_to_index[name.casefold()] for name in CANDIDATES if name.casefold() in name_to_index]
    missing = [name for name in CANDIDATES if name.casefold() not in name_to_index]
    print(json.dumps({"fishial_common_candidate_count":len(matched), "fishial_missing_candidates":missing}), flush=True)
    rows = []
    for expected, path in public_photos():
        with Image.open(path) as source:
            image = ImageOps.exif_transpose(source).convert("RGB")
            if image.height > image.width:
                image = image.transpose(Image.Transpose.ROTATE_90)
            array = np.asarray(image).copy()
        tensor = torch.from_numpy(array).permute(2, 0, 1).unsqueeze(0).float().div_(255)
        tensor = torch.nn.functional.interpolate(tensor, size=(154, 434), mode="bilinear", align_corners=False)
        tensor = (tensor-mean)/std
        begin = time.perf_counter()
        with torch.inference_mode():
            embedding, _ = model(tensor)
            scores = torch.nn.functional.normalize(embedding, p=2, dim=1) @ centroids.T
            by_class = torch.full((1, len(labels)), float("-inf"))
            by_class.scatter_reduce_(1, classes, scores, reduce="amax", include_self=False)
            indices = by_class.topk(5, dim=1).indices[0].tolist()
            subset_indices = by_class[0, matched].topk(min(5, len(matched))).indices.tolist()
        names = [labels[str(index)]["label"] for index in indices]
        subset = [labels[str(matched[index])]["label"] for index in subset_indices]
        rows.append({"expected":expected, "predictions":names, "matched_candidates_predictions":subset, "matched_candidates_top1":subset[0].casefold() == expected, "matched_candidates_top5":expected in [name.casefold() for name in subset], "top1":names[0].casefold() == expected, "top5":expected in [name.casefold() for name in names], "seconds":round(time.perf_counter()-begin, 3)})
    report("Fishial v0.10.2; full label set", rows, start)


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"bioclip", "fishial"}:
        raise SystemExit("Expected bioclip or fishial")
    {"bioclip": bioclip, "fishial": fishial}[sys.argv[1]]()
