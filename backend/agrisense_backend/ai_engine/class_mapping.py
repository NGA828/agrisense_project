"""Class-manifest parsing for plant-pathology models.

A classifier's output is only useful when output index ``n`` can be mapped to a
crop, a disease in the AgriSense knowledge base, or a healthy class.  Keeping
that mapping next to the model avoids the dangerous assumption that database
row order and model output order are the same.

The preferred manifest format is::

    {
      "classes": [
        {"index": 0, "label": "Tomato___Early_blight",
         "crop_type": "Tomato", "disease_name": "Tomato Early Blight"},
        {"index": 1, "label": "Tomato___healthy",
         "crop_type": "Tomato", "is_healthy": true}
      ]
    }

For interoperability, a plain list, a Hugging Face ``id2label`` mapping, and a
Keras ``class_indices`` mapping (label -> index) are accepted too.  In those
formats crop/disease fields are inferred from common PlantVillage-style labels;
production deployments should prefer explicit entries.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


class ClassMapError(ValueError):
    """Raised when a model class manifest is missing or internally invalid."""


@dataclass(frozen=True)
class ModelClass:
    """Meaning of one classifier output index."""

    index: int
    label: str
    crop_type: str
    disease_name: str
    is_healthy: bool = False


_CROP_ALIASES = {
    'corn': 'Maize',
    'corn maize': 'Maize',
    'maize': 'Maize',
    'bell pepper': 'Pepper',
    'pepper bell': 'Pepper',
    'pepper': 'Pepper',
    'tomato': 'Tomato',
    'cassava': 'Cassava',
    'cocoa': 'Cocoa',
    'apple': 'Apple',
    'blueberry': 'Blueberry',
    'cherry': 'Cherry',
    'grape': 'Grape',
    'orange': 'Orange',
    'peach': 'Peach',
    'potato': 'Potato',
    'raspberry': 'Raspberry',
    'soybean': 'Soybean',
    'soy': 'Soybean',
    'squash': 'Squash',
    'strawberry': 'Strawberry',
}

# Canonical names used by the bundled knowledge base.  Explicit manifest
# ``disease_name`` values always win over these conveniences.
_DISEASE_ALIASES = {
    ('Maize', 'cercospora leaf spot gray leaf spot'): 'Maize Gray Leaf Spot',
    ('Maize', 'gray leaf spot'): 'Maize Gray Leaf Spot',
    ('Maize', 'common rust'): 'Maize Rust',
    ('Maize', 'rust'): 'Maize Rust',
    ('Tomato', 'early blight'): 'Tomato Early Blight',
    ('Tomato', 'late blight'): 'Tomato Late Blight',
}


def _words(value: str) -> str:
    value = re.sub(r'[_\-/]+', ' ', str(value))
    value = re.sub(r'[^\w\s()]', ' ', value, flags=re.UNICODE)
    return re.sub(r'\s+', ' ', value).strip()


def _normal_key(value: str) -> str:
    value = _words(value).lower().replace('(', ' ').replace(')', ' ')
    return re.sub(r'\s+', ' ', value).strip()


def _display_words(value: str) -> str:
    """Readable title while preserving common pathogen abbreviations."""
    titled = _words(value).title()
    replacements = {
        'Cmv': 'CMV',
        'Tmv': 'TMV',
        'Virus': 'Virus',
        'Mold': 'Mold',
    }
    for old, new in replacements.items():
        titled = re.sub(rf'\b{old}\b', new, titled)
    return titled


def infer_class_fields(label: str) -> tuple[str, str, bool]:
    """Infer ``(crop, disease, healthy)`` from a common classifier label."""
    original = str(label).strip()
    # PlantVillage labels conventionally separate crop and condition with
    # triple underscores.  Preserve that boundary before normalising words.
    if '___' in original:
        crop_raw, condition_raw = original.split('___', 1)
    else:
        readable = _words(original)
        lower = _normal_key(readable)
        crop_raw = ''
        condition_raw = readable
        # Longest aliases first so "Bell Pepper" wins over "Pepper".
        aliases = sorted(_CROP_ALIASES, key=len, reverse=True)
        for alias in aliases:
            if lower == alias or lower.startswith(f'{alias} '):
                crop_raw = alias
                condition_raw = readable[len(alias):].strip()
                break
        # Some exported configs phrase healthy classes as "Healthy Tomato
        # Plant". Find a crop elsewhere only when no leading crop matched.
        if not crop_raw:
            padded = f' {lower} '
            for alias in aliases:
                if f' {alias} ' in padded:
                    crop_raw = alias
                    condition_raw = re.sub(
                        rf'\b{re.escape(alias)}\b', '', readable,
                        count=1, flags=re.IGNORECASE).strip()
                    break

    crop_key = _normal_key(crop_raw)
    crop = _CROP_ALIASES.get(crop_key, _display_words(crop_raw))

    condition = _words(condition_raw)
    condition = re.sub(r'^with\s+', '', condition, flags=re.IGNORECASE)
    # Labels such as "Corn (Maize) with Common Rust" leave punctuation-free
    # aliases in the condition after the leading crop has been removed.
    condition_key = _normal_key(condition)
    healthy = bool(re.search(r'\b(healthy|health|normal)\b', condition_key))
    if healthy:
        return crop, 'Healthy', True

    canonical = _DISEASE_ALIASES.get((crop, condition_key))
    if canonical:
        disease_name = canonical
    else:
        condition_display = _display_words(condition) or 'Unknown Condition'
        disease_name = f'{crop} {condition_display}'.strip()

    return crop, disease_name, False


def _entry(index: int, value: Any) -> ModelClass:
    if isinstance(value, str):
        data = {'label': value}
    elif isinstance(value, dict):
        data = value
    else:
        raise ClassMapError(
            f'Class {index} must be a string or object, got {type(value).__name__}.')

    try:
        class_index = int(data.get('index', index))
    except (TypeError, ValueError) as exc:
        raise ClassMapError(f'Invalid class index {data.get("index")!r}.') from exc
    if class_index < 0:
        raise ClassMapError('Class indexes must be non-negative integers.')

    label = str(data.get('label') or data.get('name') or '').strip()
    if not label:
        raise ClassMapError(f'Class {class_index} has no label.')

    inferred_crop, inferred_disease, inferred_healthy = infer_class_fields(label)
    crop_type = str(data.get('crop_type') or data.get('crop') or inferred_crop).strip()
    is_healthy = bool(data.get('is_healthy', data.get('healthy', inferred_healthy)))
    disease_name = str(data.get('disease_name') or inferred_disease).strip()
    if is_healthy:
        disease_name = 'Healthy'
    if not crop_type:
        raise ClassMapError(
            f'Class {class_index} ({label!r}) has no crop_type; add it explicitly.')
    if not disease_name:
        raise ClassMapError(
            f'Class {class_index} ({label!r}) has no disease_name; add it explicitly.')

    return ModelClass(
        index=class_index,
        label=label,
        crop_type=crop_type,
        disease_name=disease_name,
        is_healthy=is_healthy,
    )


def parse_class_map(data: Any) -> list[ModelClass]:
    """Parse any supported class-map representation into sorted entries."""
    if isinstance(data, dict) and 'classes' in data:
        data = data['classes']
    elif isinstance(data, dict) and 'id2label' in data:
        data = data['id2label']

    raw_entries: Iterable[tuple[int, Any]]
    if isinstance(data, list):
        raw_entries = enumerate(data)
    elif isinstance(data, dict):
        # Keras class_indices uses label -> integer; id2label uses integer ->
        # label.  Object values under numeric keys are also accepted.
        if data and all(isinstance(value, int) for value in data.values()):
            raw_entries = ((int(index), label) for label, index in data.items())
        else:
            converted = []
            for key, value in data.items():
                try:
                    index = int(key)
                except (TypeError, ValueError) as exc:
                    raise ClassMapError(
                        'Class-map object keys must be output indexes, or values '
                        'must be Keras class_indices integers.') from exc
                converted.append((index, value))
            raw_entries = converted
    else:
        raise ClassMapError('Class manifest must contain a list or object mapping.')

    classes = sorted((_entry(index, value) for index, value in raw_entries),
                     key=lambda item: item.index)
    if not classes:
        raise ClassMapError('Class manifest contains no classes.')

    indexes = [item.index for item in classes]
    if len(indexes) != len(set(indexes)):
        raise ClassMapError('Class manifest contains duplicate output indexes.')
    if indexes != list(range(len(indexes))):
        raise ClassMapError(
            'Class manifest indexes must be contiguous and start at zero; every '
            'model output needs an explicit mapping.')
    return classes


def load_class_map(path: str | Path) -> list[ModelClass]:
    manifest = Path(path).expanduser()
    if not manifest.is_file():
        raise ClassMapError(f'Class manifest does not exist: {manifest}')
    try:
        with manifest.open('r', encoding='utf-8') as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise ClassMapError(f'Could not read class manifest {manifest}: {exc}') from exc
    return parse_class_map(data)


def find_class_map(model_path: str | Path, configured_path: str = '') -> Path | None:
    """Find an explicit or conventional sidecar manifest for a model."""
    if configured_path:
        return Path(configured_path).expanduser()

    model = Path(model_path).expanduser()
    base = model if model.is_dir() else model.parent
    candidates = [
        base / 'class_map.json',
        base / 'classes.json',
        base / 'class_names.json',
        base / 'class_indices.json',
        base / 'config.json',  # Hugging Face config with id2label
    ]
    if model.suffix:
        candidates.insert(0, model.with_suffix('.classes.json'))
    return next((candidate for candidate in candidates if candidate.is_file()), None)
