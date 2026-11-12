
# FindMyThings - CLIP Matcher

import torch
import torch.nn.functional as F


def get_image_embedding(image, clip_model, clip_processor):
    """
    Convert an image into a normalized CLIP embedding.
    """

    inputs = clip_processor(
        images=image.convert("RGB"),
        return_tensors="pt"
    )

    with torch.no_grad():

        outputs = clip_model.vision_model(
            pixel_values=inputs["pixel_values"]
        )

        embedding = clip_model.visual_projection(
            outputs.pooler_output
        )

        embedding = F.normalize(
            embedding,
            p=2,
            dim=-1
        )

    return embedding


def calculate_similarity(candidate_embedding, reference_embedding):
    """
    Calculate cosine similarity between two image embeddings.
    """

    similarity = (
        candidate_embedding @ reference_embedding.T
    ).item()

    return similarity
