import sys
import traceback
from pathlib import Path
from tempfile import NamedTemporaryFile

# Keep Windows console logging UTF-8 safe.
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

from fastapi import BackgroundTasks, FastAPI, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from outline import generate_transparent_overlay


limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="PoseCoach Overlay API")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

_MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB

# Validate the client-provided type before processing the upload.
_ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp"}

_ALLOWED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


def _cleanup(paths: list[str]) -> None:
    for path in paths:
        try:
            Path(path).unlink(missing_ok=True)
        except OSError:
            pass


@app.post("/api/generate_overlay")
@limiter.limit("10/minute")
async def generate_overlay(
    request: Request,
    file: UploadFile,
    background_tasks: BackgroundTasks,
) -> FileResponse:
    print("\n=== NEW REQUEST ===", flush=True)

    if file.content_type not in _ALLOWED_MIME:
        print(f"[REJECT] Bad MIME: {file.content_type}", flush=True)
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported media type. Expected one of: {sorted(_ALLOWED_MIME)}",
        )

    raw_suffix = Path(file.filename or "upload.jpg").suffix.lower()
    if raw_suffix not in _ALLOWED_SUFFIXES:
        print(f"[REJECT] Bad extension: {raw_suffix!r}", flush=True)
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file extension. Allowed: {sorted(_ALLOWED_SUFFIXES)}",
        )
    safe_input_suffix = raw_suffix if raw_suffix in _ALLOWED_SUFFIXES else ".jpg"

    # Read in chunks so oversized uploads are rejected before loading fully.
    file_contents = bytearray()
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break

        file_contents.extend(chunk)
        if len(file_contents) > _MAX_UPLOAD_BYTES:
            print(
                f"[REJECT] Upload exceeds {_MAX_UPLOAD_BYTES // (1024*1024)} MB limit",
                flush=True,
            )
            raise HTTPException(
                status_code=413,
                detail=f"File too large. Maximum allowed size is {_MAX_UPLOAD_BYTES // (1024*1024)} MB.",
            )

    if len(file_contents) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    print(f"[OK] Received {len(file_contents):,} bytes (type={file.content_type})", flush=True)

    # Write the upload to a temp file and explicitly close it before processing.
    # On Windows, NamedTemporaryFile holds an exclusive lock while open, which
    # prevents OpenCV from reading the file in the same process.
    temp_in = NamedTemporaryFile(delete=False, suffix=safe_input_suffix)
    temp_in.write(bytes(file_contents))
    temp_in.close()  # Release handle so OpenCV can open the file.
    input_path = temp_in.name

    temp_out = NamedTemporaryFile(delete=False, suffix=".png")
    temp_out.close()  # Release handle so OpenCV can write the result.
    output_path = temp_out.name

    print("[START] generate_transparent_overlay() ...", flush=True)
    try:
        generate_transparent_overlay(input_path, output_path)
        print("[OK] Overlay generated successfully", flush=True)
    except Exception:
        print("[CRASH] Exception in generate_transparent_overlay():", flush=True)
        print(traceback.format_exc(), flush=True)
        _cleanup([input_path, output_path])
        raise HTTPException(status_code=500, detail="Overlay generation failed.")

    background_tasks.add_task(_cleanup, [input_path, output_path])

    print(f"[SEND] Dispatching FileResponse -> {output_path}", flush=True)
    return FileResponse(
        output_path,
        media_type="image/png",
        filename="transparent_silhouette.png",
        background=background_tasks,
    )
