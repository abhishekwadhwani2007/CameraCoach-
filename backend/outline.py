import tensorflow as tf
import sys, os, warnings
import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
warnings.filterwarnings('ignore')

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(SCRIPT_DIR, 'models', 'pose_landmark_full.tflite')

# Glow layers: radius, alpha, and BGR colour.
GLOW_LAYERS = [
    (24, 0.055, (150, 235, 190)),
    (17, 0.095, ( 95, 235, 155)),
    (11, 0.165, ( 65, 235, 125)),
    ( 6, 0.310, ( 45, 220, 105)),
    ( 3, 0.620, ( 35, 235, 115)),
    ( 1, 0.860, (185, 245, 205)),
]

BODY_SEGMENTS = [
    (11, 12, 0.35),
    (11, 23, 0.22),
    (12, 24, 0.22),
    (11, 13, 0.27),
    (13, 15, 0.23),
    (12, 14, 0.27),
    (14, 16, 0.23),
    (23, 25, 0.18),
    (25, 27, 0.14),
    (24, 26, 0.18),
    (26, 28, 0.14),
]

BODY_JOINTS = [
    (0,  0.14),
    (11, 0.13),
    (12, 0.13),
    (13, 0.13),
    (14, 0.13),
    (15, 0.22),
    (16, 0.22),
    (23, 0.12),
    (24, 0.12),
    (25, 0.10),
    (26, 0.10),
    (27, 0.08),
    (28, 0.08),
]

HAND_LANDMARKS = [
    (17, 0.10),
    (19, 0.10),
    (18, 0.10),
    (20, 0.10),
]


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-np.clip(x, -50, 50)))


def run_pose(img_bgr: np.ndarray):
    H, W = img_bgr.shape[:2]
    interp = tf.lite.Interpreter(model_path=MODEL_PATH)
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    SZ = inp['shape'][1]

    rgb = cv2.cvtColor(cv2.resize(img_bgr, (SZ, SZ)),
                       cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    interp.set_tensor(inp['index'], np.expand_dims(rgb, 0))
    interp.invoke()

    raw     = interp.get_tensor(interp.get_output_details()[0]['index'])[0]
    score   = interp.get_tensor(interp.get_output_details()[1]['index'])[0][0]
    seg_raw = interp.get_tensor(interp.get_output_details()[2]['index'])[0, :, :, 0]

    lms = raw.reshape(39, 5).copy()
    lms[:, 0] = lms[:, 0] / SZ * W
    lms[:, 1] = lms[:, 1] / SZ * H

    seg_prob = sigmoid(seg_raw)
    seg_mask = cv2.resize(seg_prob, (W, H), interpolation=cv2.INTER_LINEAR)
    return lms, float(score), seg_mask


def _get_body_scale(lms: np.ndarray) -> float:
    l_sh, r_sh = lms[11], lms[12]
    l_hp, r_hp = lms[23], lms[24]
    if l_sh[3] > 0.3 and r_sh[3] > 0.3:
        d = np.linalg.norm(l_sh[:2] - r_sh[:2])
        if d > 20:
            return d
    if l_hp[3] > 0.3 and r_hp[3] > 0.3:
        d = np.linalg.norm(l_hp[:2] - r_hp[:2])
        if d > 20:
            return d * 1.3
    return 100.0


def _draw_arm_force_fg(force_fg: np.ndarray, lms: np.ndarray, body_scale: float):
    """Paint thick arm strokes into force_fg so GrabCut cannot erase them."""
    arm_chains = [
        (11, 13, 15),   # left arm
        (12, 14, 16),   # right arm
    ]
    thick = max(6, int(body_scale * 0.30))
    for idx_sh, idx_el, idx_wr in arm_chains:
        sh, el, wr = lms[idx_sh], lms[idx_el], lms[idx_wr]
        if sh[3] > 0.20 and el[3] > 0.20:
            cv2.line(force_fg,
                     (int(sh[0]), int(sh[1])),
                     (int(el[0]), int(el[1])),
                     255, thickness=thick, lineType=cv2.LINE_AA)
        if el[3] > 0.20 and wr[3] > 0.20:
            cv2.line(force_fg,
                     (int(el[0]), int(el[1])),
                     (int(wr[0]), int(wr[1])),
                     255, thickness=thick, lineType=cv2.LINE_AA)


def _build_kettlebell_ellipse(lms: np.ndarray, body_scale: float,
                               H: int, W: int):
    """Build a tight kettlebell ellipse in front of close wrists."""
    lw, rw = lms[15], lms[16]
    if lw[3] < 0.3 or rw[3] < 0.3:
        return None

    wrist_dist = np.linalg.norm(lw[:2] - rw[:2])
    if wrist_dist >= body_scale * 1.2:
        return None

    l_sh, r_sh = lms[11], lms[12]
    if l_sh[3] > 0.2 and r_sh[3] > 0.2:
        torso_cx = (l_sh[0] + r_sh[0]) / 2.0
    else:
        torso_cx = W / 2.0

    mid = (lw[:2] + rw[:2]) / 2.0

    ball_r  = max(12, int(wrist_dist * 0.40))
    offset_dir = np.sign(mid[0] - torso_cx)
    nudge      = offset_dir * max(4, int(wrist_dist * 0.15))
    ell_cx     = int(mid[0] + nudge)

    ball_cy_est = mid[1] + wrist_dist * 0.30
    ell_cy  = int(mid[1] + wrist_dist * 0.10)

    ell_rx  = ball_r + max(3, int(wrist_dist * 0.08))
    ell_ry  = max(ball_r, int(ball_cy_est - ell_cy) + ball_r)

    return (ell_cx, ell_cy, ell_rx, ell_ry)


def _detect_kettlebell_ellipse(img_bgr: np.ndarray, lms: np.ndarray,
                               body_scale: float):
    """Find the dark kettlebell mass in front of the wrists via pixel search."""
    H, W = img_bgr.shape[:2]
    lw, rw = lms[15], lms[16]
    if lw[3] < 0.15 and rw[3] < 0.15:
        return _build_kettlebell_ellipse(lms, body_scale, H, W)

    if lw[3] > 0.15 and rw[3] > 0.15:
        mid = (lw[:2] + rw[:2]) * 0.5
    else:
        mid = lw[:2] if lw[3] > rw[3] else rw[:2]

    l_sh, r_sh = lms[11], lms[12]
    torso_cx = (l_sh[0] + r_sh[0]) * 0.5 if l_sh[3] > 0.2 and r_sh[3] > 0.2 else W * 0.5
    side = -1 if mid[0] < torso_cx else 1

    if side < 0:
        x1 = max(0, int(mid[0] - body_scale * 4.0))
        x2 = min(W, int(mid[0] + body_scale * 0.8))
    else:
        x1 = max(0, int(mid[0] - body_scale * 0.8))
        x2 = min(W, int(mid[0] + body_scale * 4.0))
    y1 = max(0, int(mid[1] - body_scale * 1.8))
    y2 = min(H, int(mid[1] + body_scale * 1.8))
    if x2 <= x1 or y2 <= y1:
        return _build_kettlebell_ellipse(lms, body_scale, H, W)

    roi = img_bgr[y1:y2, x1:x2]
    hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    dark = ((gray < 96) & (hsv[:, :, 1] > 12)).astype(np.uint8) * 255
    k = max(5, int(body_scale * 0.08)) | 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE, kernel, iterations=2)
    dark = cv2.morphologyEx(dark, cv2.MORPH_OPEN, kernel, iterations=1)

    count, labels, stats, centroids = cv2.connectedComponentsWithStats(dark, 8)
    best = None
    best_score = -1.0
    for label in range(1, count):
        x, y, w, h, area = stats[label]
        if area < body_scale * body_scale * 0.25:
            continue
        if area > body_scale * body_scale * 3.5:
            continue
        cx, cy = centroids[label]
        global_cx = x1 + cx
        global_cy = y1 + cy
        in_front = (global_cx - mid[0]) * side > -body_scale * 0.25
        near_hand = abs(global_cy - mid[1]) < body_scale * 1.1
        if not in_front or not near_hand:
            continue
        aspect_score = 1.0 - min(1.0, abs((w / max(1, h)) - 1.35) / 1.35)
        distance = abs(global_cx - mid[0])
        score = area * (0.65 + aspect_score) - distance * body_scale * 0.6
        if score > best_score:
            best_score = score
            best = label

    if best is None:
        return _build_kettlebell_ellipse(lms, body_scale, H, W)

    x, y, w, h, _ = stats[best]
    component = labels == best
    if side < 0:
        limit = x + max(1, int(w * 0.43))
        ys, xs = np.where(component[:, :limit] > 0)
    else:
        start = x + min(w - 1, int(w * 0.57))
        ys, xs = np.where(component[:, start:] > 0)
        xs = xs + start
    if len(xs) < 20:
        cx, cy = centroids[best]
        ball_x1, ball_x2, ball_y1, ball_y2 = x, x + w, y, y + h
    else:
        cx, cy = float(xs.mean()), float(ys.mean())
        ball_x1, ball_x2 = int(xs.min()), int(xs.max())
        ball_y1, ball_y2 = int(ys.min()), int(ys.max())

    ell_cx = int(x1 + cx + side * body_scale * 0.03)
    ell_cy = int(y1 + cy)
    ell_rx = max(int((ball_x2 - ball_x1) * 0.55), int(body_scale * 0.48))
    ell_ry = max(int((ball_y2 - ball_y1) * 0.62), int(body_scale * 0.50))
    ell_rx = min(ell_rx, int(body_scale * 0.72))
    ell_ry = min(ell_ry, int(body_scale * 0.70))
    return (ell_cx, ell_cy, ell_rx, ell_ry)


def build_skeleton_mask(H: int, W: int, lms: np.ndarray,
                        kettlebell_ellipse=None) -> np.ndarray:
    body_scale = _get_body_scale(lms)
    mask = np.zeros((H, W), dtype=np.uint8)

    for idx_a, idx_b, width_ratio in BODY_SEGMENTS:
        a, b = lms[idx_a], lms[idx_b]
        if a[3] < 0.25 or b[3] < 0.25:
            continue
        pt1 = (int(a[0]), int(a[1]))
        pt2 = (int(b[0]), int(b[1]))
        thick = max(4, int(body_scale * width_ratio))
        cv2.line(mask, pt1, pt2, 255, thickness=thick, lineType=cv2.LINE_AA)

    for idx, radius_ratio in BODY_JOINTS:
        pt = lms[idx]
        if pt[3] < 0.25:
            continue
        r = max(3, int(body_scale * radius_ratio))
        cv2.circle(mask, (int(pt[0]), int(pt[1])), r, 255, thickness=-1,
                   lineType=cv2.LINE_AA)

    for idx, radius_ratio in HAND_LANDMARKS:
        pt = lms[idx]
        if pt[3] < 0.20:
            continue
        r = max(3, int(body_scale * radius_ratio))
        cv2.circle(mask, (int(pt[0]), int(pt[1])), r, 255, thickness=-1,
                   lineType=cv2.LINE_AA)
        wrist_idx = 15 if idx in (17, 19) else 16
        wrist = lms[wrist_idx]
        if wrist[3] > 0.2:
            cv2.line(mask, (int(wrist[0]), int(wrist[1])),
                     (int(pt[0]), int(pt[1])),
                     255, thickness=max(3, int(body_scale * 0.08)),
                     lineType=cv2.LINE_AA)

    nose = lms[0]
    l_ear, r_ear = lms[7], lms[8]
    if l_ear[3] > 0.3 and r_ear[3] > 0.3:
        cx = int((l_ear[0] + r_ear[0]) / 2)
        cy = int((l_ear[1] + r_ear[1]) / 2)
        ear_span = abs(l_ear[0] - r_ear[0])
        rx = int(ear_span * 0.42)
        ry = int(ear_span * 0.52)
        cv2.ellipse(mask, (cx, cy), (rx, ry), 0, 0, 360, 255, -1,
                    lineType=cv2.LINE_AA)
    elif nose[3] > 0.3:
        r = max(6, int(body_scale * 0.18))
        cv2.circle(mask, (int(nose[0]), int(nose[1])), r, 255, -1)

    ell = kettlebell_ellipse or _build_kettlebell_ellipse(lms, body_scale, H, W)
    if ell is not None:
        ell_cx, ell_cy, ell_rx, ell_ry = ell
        cv2.ellipse(mask, (ell_cx, ell_cy), (ell_rx, ell_ry),
                    0, 0, 360, 255, -1, lineType=cv2.LINE_AA)

    for ankle_idx, heel_idx, toe_idx in [(27, 29, 31), (28, 30, 32)]:
        ankle = lms[ankle_idx]
        if ankle[3] < 0.25:
            continue
        foot_r = max(4, int(body_scale * 0.12))
        cv2.circle(mask, (int(ankle[0]), int(ankle[1])), foot_r, 255, -1)
        for fi in [heel_idx, toe_idx]:
            fp = lms[fi]
            if fp[3] > 0.2:
                cv2.circle(mask, (int(fp[0]), int(fp[1])),
                           max(3, int(body_scale * 0.08)), 255, -1)
                cv2.line(mask, (int(ankle[0]), int(ankle[1])),
                         (int(fp[0]), int(fp[1])),
                         255, thickness=max(3, int(body_scale * 0.10)),
                         lineType=cv2.LINE_AA)

    return mask


def combine_masks(seg_mask: np.ndarray, skeleton_mask: np.ndarray) -> np.ndarray:
    seg_binary = (seg_mask > 0.5).astype(np.uint8) * 255
    combined = np.maximum(seg_binary, skeleton_mask)
    H, W = combined.shape[:2]
    k = max(3, int(max(H, W) * 0.003)) | 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    combined = cv2.morphologyEx(combined, cv2.MORPH_CLOSE, kernel, iterations=1)
    return combined


def refine_with_grabcut(img_bgr: np.ndarray, coarse_mask: np.ndarray,
                        iterations: int = 3,
                        floor_y: int = None,
                        force_fg: np.ndarray = None) -> np.ndarray:
    H, W = img_bgr.shape[:2]
    MAX_DIM = 800
    scale = min(MAX_DIM / max(H, W), 1.0)
    if scale < 1.0:
        small_img  = cv2.resize(img_bgr,    (int(W * scale), int(H * scale)))
        small_mask = cv2.resize(coarse_mask, (int(W * scale), int(H * scale)),
                                interpolation=cv2.INTER_NEAREST)
    else:
        small_img  = img_bgr.copy()
        small_mask = coarse_mask.copy()

    gc_mask = np.zeros(small_mask.shape[:2], dtype=np.uint8)

    k_erode  = max(3, int(min(small_mask.shape[:2]) * 0.02)) | 1
    kernel_e = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k_erode, k_erode))
    fg_core  = cv2.erode(small_mask, kernel_e, iterations=2)

    k_dilate   = max(3, int(min(small_mask.shape[:2]) * 0.03)) | 1
    kernel_d   = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k_dilate, k_dilate))
    fg_expanded = cv2.dilate(small_mask, kernel_d, iterations=2)

    gc_mask[:]                 = cv2.GC_BGD
    gc_mask[fg_expanded > 127] = cv2.GC_PR_FGD
    gc_mask[small_mask  > 127] = cv2.GC_PR_FGD
    gc_mask[fg_core     > 127] = cv2.GC_FGD

    if force_fg is not None:
        fs = cv2.resize(force_fg, (small_img.shape[1], small_img.shape[0]),
                        interpolation=cv2.INTER_NEAREST)
        gc_mask[fs > 127] = cv2.GC_FGD

    if floor_y is not None:
        fy = min(int(floor_y * scale), gc_mask.shape[0] - 1)
        gc_floor = np.full(gc_mask[fy:].shape, cv2.GC_BGD, dtype=np.uint8)
        gc_floor[small_mask[fy:] > 127] = cv2.GC_PR_FGD
        gc_mask[fy:] = gc_floor

    bgd_model = np.zeros((1, 65), np.float64)
    fgd_model = np.zeros((1, 65), np.float64)
    try:
        cv2.grabCut(small_img, gc_mask, None, bgd_model, fgd_model,
                    iterations, cv2.GC_INIT_WITH_MASK)
    except cv2.error:
        return coarse_mask

    refined = np.where((gc_mask == cv2.GC_FGD) | (gc_mask == cv2.GC_PR_FGD),
                       255, 0).astype(np.uint8)
    if scale < 1.0:
        refined = cv2.resize(refined, (W, H), interpolation=cv2.INTER_LINEAR)
        refined = (refined > 127).astype(np.uint8) * 255
    return refined


def smooth_hair_neck_mask(binary_mask: np.ndarray, lms: np.ndarray,
                          body_scale: float) -> np.ndarray:
    nose = lms[0]
    l_ear, r_ear = lms[7], lms[8]
    l_sh, r_sh = lms[11], lms[12]
    if (nose[3] < 0.20 or l_ear[3] < 0.20 or r_ear[3] < 0.20 or
            l_sh[3] < 0.20 or r_sh[3] < 0.20):
        return binary_mask

    H, W = binary_mask.shape[:2]
    head_mid = (l_ear[:2] + r_ear[:2]) * 0.5
    shoulder_y = min(l_sh[1], r_sh[1])
    face_dir = -1 if nose[0] < head_mid[0] else 1
    back_dir = -face_dir

    x1 = max(0, int(min(nose[0], head_mid[0] + back_dir * body_scale * 1.85) -
                    body_scale * 0.22))
    x2 = min(W, int(max(nose[0], head_mid[0] + back_dir * body_scale * 1.85) +
                    body_scale * 0.22))
    y1 = max(0, int(min(nose[1], l_ear[1], r_ear[1]) - body_scale * 1.05))
    y2 = min(H, int(shoulder_y + body_scale * 0.10))
    if x2 <= x1 or y2 <= y1:
        return binary_mask

    cleaned = binary_mask.copy()
    roi = cleaned[y1:y2, x1:x2]

    close_k = max(3, int(body_scale * 0.040)) | 1
    blur_k = max(5, int(body_scale * 0.065)) | 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (close_k, close_k))
    smooth = cv2.morphologyEx(roi, cv2.MORPH_CLOSE, kernel, iterations=1)
    smooth = cv2.GaussianBlur(smooth, (blur_k, blur_k), 0)
    smooth = (smooth > 112).astype(np.uint8) * 255

    seed = np.zeros_like(roi)
    cv2.ellipse(seed,
                (int(head_mid[0] - x1), int(head_mid[1] - y1)),
                (max(10, int(body_scale * 0.42)),
                 max(12, int(body_scale * 0.58))),
                0, 0, 360, 255, -1, lineType=cv2.LINE_AA)
    cv2.line(seed,
             (int(head_mid[0] - x1), int(head_mid[1] - y1)),
             (int((head_mid[0] + back_dir * body_scale * 1.20) - x1),
              int((head_mid[1] + body_scale * 0.22) - y1)),
             255, thickness=max(8, int(body_scale * 0.24)),
             lineType=cv2.LINE_AA)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(smooth, 8)
    keep = np.zeros_like(roi)
    for label in range(1, count):
        component = labels == label
        if stats[label, cv2.CC_STAT_AREA] > body_scale * body_scale * 0.08:
            if np.any(seed[component] > 0):
                keep[component] = 255

    if np.any(keep):
        roi[keep > 0] = keep[keep > 0]
        cleaned[y1:y2, x1:x2] = roi
    return cleaned


def _smooth_contour(contour: np.ndarray, sigma: float = 3.0,
                    num_points: int = 400) -> np.ndarray:
    pts = contour.reshape(-1, 2).astype(np.float64)
    n = len(pts)
    if n < 5:
        return contour
    diffs    = np.diff(pts, axis=0)
    seg_lens = np.sqrt((diffs ** 2).sum(axis=1))
    cum_len  = np.concatenate(([0], np.cumsum(seg_lens)))
    total_len = cum_len[-1]
    if total_len < 1:
        return contour
    target_n = max(num_points, n)
    even_t   = np.linspace(0, total_len, target_n, endpoint=False)
    xs = np.interp(even_t, cum_len, pts[:, 0])
    ys = np.interp(even_t, cum_len, pts[:, 1])
    xs_smooth = gaussian_filter1d(xs, sigma=sigma, mode='wrap')
    ys_smooth = gaussian_filter1d(ys, sigma=sigma, mode='wrap')
    smoothed  = np.stack([xs_smooth, ys_smooth], axis=1)
    return smoothed.reshape(-1, 1, 2).astype(np.int32)


def extract_body_contours(binary_mask: np.ndarray,
                          min_area_frac: float = 0.001,
                          smooth_sigma: float = 3.0):
    H, W = binary_mask.shape[:2]
    total_area = H * W

    ksize  = max(3, int(max(H, W) * 0.002)) | 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksize, ksize))
    binary_mask = cv2.morphologyEx(binary_mask, cv2.MORPH_CLOSE, kernel, iterations=1)
    binary_mask = cv2.morphologyEx(binary_mask, cv2.MORPH_OPEN,  kernel, iterations=1)

    blur_k = max(5, int(max(H, W) * 0.008)) | 1
    binary_mask = cv2.GaussianBlur(binary_mask, (blur_k, blur_k), 0)
    binary_mask = (binary_mask > 127).astype(np.uint8) * 255

    contours, hierarchy = cv2.findContours(binary_mask, cv2.RETR_CCOMP,
                                           cv2.CHAIN_APPROX_NONE)
    if not contours or hierarchy is None:
        return None

    h = hierarchy[0]
    best_idx, best_area = -1, 0
    for i in range(len(contours)):
        if h[i][3] == -1:
            area = cv2.contourArea(contours[i])
            if area > best_area:
                best_area = area
                best_idx  = i
    if best_idx < 0:
        return None

    result = [_smooth_contour(contours[best_idx], sigma=smooth_sigma,
                               num_points=600)]

    child_idx = h[best_idx][2]
    while child_idx != -1:
        hole = contours[child_idx]
        if cv2.contourArea(hole) > total_area * min_area_frac:
            result.append(_smooth_contour(hole, sigma=smooth_sigma * 0.7,
                                          num_points=300))
        child_idx = h[child_idx][0]

    return result if result else None


def draw_glow_outline(canvas: np.ndarray, contours: list,
                      base: int) -> np.ndarray:
    scale = base / 800.0
    for raw_thick, alpha, color in GLOW_LAYERS:
        thick   = max(1, int(raw_thick * scale))
        overlay = canvas.copy()
        for contour in contours:
            cv2.drawContours(overlay, [contour], -1, color,
                             thickness=thick, lineType=cv2.LINE_AA)
        cv2.addWeighted(overlay, alpha, canvas, 1.0 - alpha, 0, canvas)
    return canvas


def _resize_mask_to_portrait_canvas(binary_mask: np.ndarray,
                                    dst_w: int,
                                    dst_h: int,
                                    fill_height: float = 0.85) -> np.ndarray:
    ys, xs = np.where(binary_mask > 0)
    if len(xs) == 0 or len(ys) == 0:
        raise RuntimeError('Could not extract a body mask from the body image.')

    src_h, src_w = binary_mask.shape[:2]
    x1, x2 = xs.min(), xs.max()
    y1, y2 = ys.min(), ys.max()
    figure_h = max(1, y2 - y1)
    scale = (dst_h * fill_height) / figure_h

    scaled_w = max(1, int(round(src_w * scale)))
    scaled_h = max(1, int(round(src_h * scale)))
    scaled = cv2.resize(binary_mask, (scaled_w, scaled_h),
                        interpolation=cv2.INTER_CUBIC)

    scaled_x1 = int(round(x1 * scale))
    scaled_x2 = int(round(x2 * scale))
    scaled_y1 = int(round(y1 * scale))
    scaled_y2 = int(round(y2 * scale))
    figure_w = max(1, scaled_x2 - scaled_x1)
    figure_h = max(1, scaled_y2 - scaled_y1)

    paste_x = int(round((dst_w - figure_w) / 2.0 - scaled_x1))
    paste_y = int(round((dst_h - figure_h) / 2.0 - scaled_y1))

    canvas_mask = np.zeros((dst_h, dst_w), dtype=np.float32)
    src_x1 = max(0, -paste_x)
    src_y1 = max(0, -paste_y)
    src_x2 = min(scaled_w, dst_w - paste_x)
    src_y2 = min(scaled_h, dst_h - paste_y)
    dst_x1 = max(0, paste_x)
    dst_y1 = max(0, paste_y)
    dst_x2 = dst_x1 + max(0, src_x2 - src_x1)
    dst_y2 = dst_y1 + max(0, src_y2 - src_y1)
    if dst_x2 <= dst_x1 or dst_y2 <= dst_y1:
        raise RuntimeError('Scaled body mask does not overlap the portrait canvas.')

    canvas_mask[dst_y1:dst_y2, dst_x1:dst_x2] = (
        scaled[src_y1:src_y2, src_x1:src_x2].astype(np.float32) / 255.0
    )
    return np.clip(canvas_mask, 0.0, 1.0)


def _render_raster_neon_rgba(canvas_mask: np.ndarray) -> np.ndarray:
    h, w = canvas_mask.shape[:2]
    base = max(h, w)
    mask_u8 = np.clip(canvas_mask * 255.0, 0, 255).astype(np.uint8)

    k = max(5, int(base * 0.006)) | 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    dilated = cv2.dilate(mask_u8, kernel, iterations=1)
    eroded = cv2.erode(mask_u8, kernel, iterations=1)
    edge = cv2.subtract(dilated, eroded).astype(np.float32) / 255.0

    glow = np.zeros_like(edge, dtype=np.float32)
    color_acc = np.zeros((h, w, 3), dtype=np.float32)
    for raw_radius, alpha, color in GLOW_LAYERS:
        # Scale the blur with canvas size while preserving separation between limbs.
        sigma = max(0.8, raw_radius * base / 1400.0)
        layer = cv2.GaussianBlur(edge, (0, 0), sigmaX=sigma, sigmaY=sigma)
        layer = np.clip(layer * alpha * 2.2, 0.0, 1.0)
        glow = np.maximum(glow, layer)
        bgr = np.array(color, dtype=np.float32) / 255.0
        color_acc += layer[..., None] * bgr

    core = cv2.GaussianBlur(edge, (0, 0), sigmaX=0.65, sigmaY=0.65)
    core = np.clip(core * 0.95, 0.0, 1.0)
    color_acc += core[..., None] * np.array((185, 245, 205),
                                            dtype=np.float32) / 255.0
    alpha_ch = np.clip(glow + core, 0.0, 1.0)

    rgb = np.divide(color_acc, np.maximum(alpha_ch[..., None], 1e-6))
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(rgb * 255.0, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = np.clip(alpha_ch * 255.0, 0, 255).astype(np.uint8)
    return rgba


def _vector_smooth_canvas_mask(canvas_mask: np.ndarray) -> np.ndarray:
    mask_u8 = np.clip(canvas_mask * 255.0, 0, 255).astype(np.uint8)
    contours, hierarchy = cv2.findContours(mask_u8, cv2.RETR_CCOMP,
                                           cv2.CHAIN_APPROX_NONE)
    if not contours or hierarchy is None:
        return canvas_mask

    smooth_mask = np.zeros_like(mask_u8)
    smoothed_contours = []
    for contour in contours:
        arc = cv2.arcLength(contour, True)
        epsilon = 0.0008 * arc
        decimated = cv2.approxPolyDP(contour, epsilon, True)
        point_count = max(600, len(decimated) * 8)
        smoothed = _smooth_contour(decimated, sigma=4.5,
                                   num_points=point_count)
        smoothed_contours.append(smoothed)

    cv2.drawContours(smooth_mask, smoothed_contours, -1, 255,
                     thickness=-1, lineType=cv2.LINE_AA)
    return smooth_mask.astype(np.float32) / 255.0


def restore_head_neck_interior(canvas: np.ndarray, original: np.ndarray,
                               binary_mask: np.ndarray, lms: np.ndarray,
                               body_scale: float) -> None:
    nose = lms[0]
    l_ear, r_ear = lms[7], lms[8]
    l_sh, r_sh = lms[11], lms[12]
    if (nose[3] < 0.20 or l_ear[3] < 0.20 or r_ear[3] < 0.20 or
            l_sh[3] < 0.20 or r_sh[3] < 0.20):
        return

    H, W = binary_mask.shape[:2]
    pts = np.array([nose[:2], l_ear[:2], r_ear[:2], l_sh[:2], r_sh[:2]])
    x1 = max(0, int(pts[:, 0].min() - body_scale * 0.45))
    x2 = min(W, int(pts[:, 0].max() + body_scale * 1.55))
    y1 = max(0, int(pts[:, 1].min() - body_scale * 1.05))
    y2 = min(H, int(min(l_sh[1], r_sh[1]) + body_scale * 0.04))
    if x2 <= x1 or y2 <= y1:
        return

    roi_mask = binary_mask[y1:y2, x1:x2]
    dist = cv2.distanceTransform((roi_mask > 0).astype(np.uint8), cv2.DIST_L2, 5)
    alpha = np.clip((dist - body_scale * 0.10) / (body_scale * 0.12), 0, 1)
    alpha = cv2.GaussianBlur(alpha.astype(np.float32),
                             (max(5, int(body_scale * 0.05)) | 1,) * 2, 0)

    canvas_roi = canvas[y1:y2, x1:x2]
    original_roi = original[y1:y2, x1:x2]
    canvas[y1:y2, x1:x2] = (
        canvas_roi * (1.0 - alpha[..., None]) +
        original_roi * alpha[..., None]
    ).astype(np.uint8)




def extract_body_mask_from_image(body_image_path: str) -> tuple[np.ndarray, tuple[int, int]]:
    """
    Run pose detection on a body image and return the refined binary body mask
    along with the source image dimensions (H, W).
    """
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(f'Model not found at {MODEL_PATH}')

    print(f'[1/3] Loading body image -> {body_image_path}')
    img = cv2.imread(body_image_path)
    if img is None:
        raise FileNotFoundError(f'Cannot read: {body_image_path}')
    H, W = img.shape[:2]
    print(f'      Size: {W}x{H}px')

    print('[2/3] Running pose landmark model ...')
    lms, score, seg_mask = run_pose(img)
    print(f'      Pose confidence: {score:.3f}')

    print('[3/3] Extracting refined body mask ...')
    body_sc   = _get_body_scale(lms)
    kettle_ell = _detect_kettlebell_ellipse(img, lms, body_sc)
    skeleton  = build_skeleton_mask(H, W, lms, kettle_ell)
    coarse    = combine_masks(seg_mask, skeleton)

    heel_toe = [29, 30, 31, 32]
    ht_ys = [int(lms[fi][1]) for fi in heel_toe if lms[fi][3] > 0.15]
    if not ht_ys:
        ht_ys = [int(lms[fi][1]) for fi in [27, 28] if lms[fi][3] > 0.15]
    floor_y = (max(ht_ys) + int(H * 0.025)) if ht_ys else None

    force_fg = np.zeros((H, W), dtype=np.uint8)
    _draw_arm_force_fg(force_fg, lms, body_sc)
    if kettle_ell is not None:
        ell_cx, ell_cy, ell_rx, ell_ry = kettle_ell
        cv2.ellipse(force_fg, (ell_cx, ell_cy), (ell_rx, ell_ry),
                    0, 0, 360, 255, -1, lineType=cv2.LINE_AA)

    binary   = refine_with_grabcut(img, coarse, iterations=3,
                                   floor_y=floor_y, force_fg=force_fg)
    binary   = smooth_hair_neck_mask(binary, lms, body_sc)

    return binary, (H, W)


def generate_transparent_overlay(body_image_path: str,
                                 output_path: str,
                                 canvas_size: tuple[int, int] = (1080, 1920)) -> None:
    """
    Generate a transparent RGBA neon silhouette PNG for live camera overlay.
    The output canvas defaults to a 1080x1920 mobile portrait frame with
    alpha=0 everywhere except the raster glow.
    """
    dst_W, dst_H = canvas_size
    print(f'[+] Transparent canvas -> {dst_W}x{dst_H}px RGBA')
    binary, (src_H, src_W) = extract_body_mask_from_image(body_image_path)
    print(f'    Source mask size: {src_W}x{src_H}px')
    canvas_mask = _resize_mask_to_portrait_canvas(binary, dst_W, dst_H)

    # Fill small gaps without noticeably expanding the silhouette.
    smooth_mask = cv2.GaussianBlur(
        (canvas_mask * 255.0).astype(np.uint8),
        (7, 7),
        0,
    )
    _, smooth_mask = cv2.threshold(smooth_mask, 127, 255, cv2.THRESH_BINARY)

    erode_k = max(3, int(max(dst_W, dst_H) * 0.006)) | 1
    kernel_e = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (erode_k, erode_k))
    smooth_mask = cv2.erode(smooth_mask, kernel_e, iterations=1)

    canvas_mask = smooth_mask.astype(np.float32) / 255.0
    canvas_mask = _vector_smooth_canvas_mask(canvas_mask)

    print('[+] Rendering raster neon alpha glow ...')
    rgba = _render_raster_neon_rgba(canvas_mask)

    print(f'[+] Saving transparent PNG -> {output_path}')
    cv2.imwrite(output_path, rgba)
    print('Done!')



if __name__ == '__main__':
    if len(sys.argv) == 1:
        generate_transparent_overlay(
            body_image_path='test2.png',
            output_path='transparent_silhouette.png',
        )
    elif len(sys.argv) in (2, 3):
        inp = sys.argv[1]
        out = sys.argv[2] if len(sys.argv) > 2 else inp.rsplit('.', 1)[0] + '_transparent_overlay.png'
        generate_transparent_overlay(inp, out)
    else:
        raise SystemExit(
            'Usage: python outline.py [body_image] [transparent_output.png]'
        )
