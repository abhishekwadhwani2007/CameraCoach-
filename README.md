# PoseCoach 📸

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=FastAPI&logoColor=white)
![Status](https://img.shields.io/badge/status-active-success?style=for-the-badge)

</div>

PoseCoach is a Flutter mobile app that helps a user recreate a reference pose in front of the camera. It combines on-device pose detection with a Python overlay-generation service so the user can align with a clean silhouette guide, capture the shot, and review basic photo-quality feedback.

The project is built as a practical AI photography assistant: the camera feed stays on the device, pose matching runs locally with Google ML Kit, and the optional backend converts a reference photo into a transparent coaching overlay.

---

## 👨‍💻 The Story Behind This Project

> *"The idea for PoseCoach was born out of a simple, universal problem: finding the right person to take the perfect photo."*

During a family trip to a scenic location, I asked my parents to take a photo of me. While the setting was perfect, communicating the exact pose and framing I wanted proved difficult. Recognizing that many people struggle to capture their desired shots without a professional photographer, the concept for **PoseCoach** was formed.

I teamed up with a friend to bring this idea to life. We divided the architecture—he handled the frontend UI, while I focused on the backend logic and computer vision algorithms. We started development in late February, balancing the project alongside our college mid-semester exams. Within a month and a half of rapid prototyping and trial-and-error, we had our first working version.

Our initial prototype utilized a basic stick-figure skeleton overlay to guide the subject. However, shortly after, we noticed new AI camera features in the smartphone industry providing full-body silhouette overlays. Realizing our skeleton approach lacked a premium feel and disrupted visibility, we pivoted to a **Silhouette/Doodle Overlay**.

This pivot was challenging. Building a robust backend pipeline to accurately extract a clean silhouette from any user-provided reference photo took nearly two months of iteration. To streamline the photography experience, we also implemented an **auto-capture workflow**: once the user aligns with the overlay and hits a >97% pose match score, the app automatically initiates a 3-second cancelable countdown before taking the photo.

### 🚧 Current Hurdles & Next Steps
Extracting and displaying the overlay flawlessly in real-time remains a complex challenge. In the current version, the overlay scale is static—for example, if a 22-year-old adult uses a reference photo of a 15-year-old, the silhouette's proportions won't perfectly match the adult's body shape and size. 

Our primary focus for the next version is implementing **dynamic overlay retargeting**, allowing the silhouette to intelligently scale and adjust to the live user's unique body proportions.

---

## 💡 Key Features

- **Reference Photo Selection**: Import desired poses directly from the gallery.
- **Smart Overlay Generation**: Transparent silhouette creation via a FastAPI backend.
- **On-Device Pose Detection**: Real-time pose analysis using Google ML Kit.
- **Live Match Scoring**: Continuous visual feedback on how well the user matches the reference.
- **Auto-Capture Flow**: Automatic 3-second countdown when a 97%+ match is achieved.
- **Photo Quality Analysis**: Evaluates exposure, depth, dynamic range, and color balance.
- **Native Camera Controls**: Adjust ISO, shutter speed, white balance, and exposure directly.

---

## 🛠️ Tech Stack

- **Frontend**: Flutter and Dart
- **Computer Vision (Mobile)**: Google ML Kit Pose Detection
- **Computer Vision (Backend)**: OpenCV, NumPy, SciPy, and TensorFlow
- **Backend API**: FastAPI (Python)
- **Local Storage**: `flutter_secure_storage` and `shared_preferences`

---

## 📂 Project Structure

```text
pose_coach/
|-- android/                  # Android runner and native camera plugin
|-- assets/
|   |-- images/               # App image assets
|   `-- models/               # TensorFlow Lite model assets
|-- backend/
|   |-- models/               # Backend TFLite model
|   |-- outline.py            # Silhouette and neon overlay generation
|   |-- requirements.txt      # Python dependencies
|   `-- server.py             # FastAPI upload endpoint
|-- ios/                      # iOS runner and native camera plugin
|-- lib/
|   |-- core/                 # Theme and app constants
|   |-- features/             # Home, onboarding, review, and live session UI
|   |-- models/               # Reference model
|   |-- services/             # Camera, pose, storage, backend, and analysis services
|   |-- utils/                # Logging helpers
|   `-- widgets/              # Reusable UI components
|-- test/                     # Flutter unit and widget tests
`-- pubspec.yaml
```

---

## ⚡ Getting Started

### 1️⃣ Prerequisites

- Flutter SDK 3.4 or newer
- Python 3.10 or newer
- Android Studio or Xcode for device builds

### 2️⃣ Backend Setup

```bash
cd backend
python -m venv venv
```

**Windows:**
```bash
venv\Scripts\activate
```

**macOS/Linux:**
```bash
source venv/bin/activate
```

Install dependencies and start the API:
```bash
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000 --reload
```

The overlay endpoint will be available at: `http://localhost:8000/api/generate_overlay`
*(Note: When running on a physical phone, use your computer's LAN IP address instead of `localhost`.)*

### 3️⃣ Flutter Setup

Install packages:
```bash
flutter pub get
```

Run the app with your backend URL:
```bash
flutter run --dart-define=BACKEND_URL=http://YOUR_PC_IP:8000
```

Alternatively, you can keep local launch values in `.env.json`:
```json
{
  "BACKEND_URL": "http://YOUR_PC_IP:8000"
}
```
Then run:
```bash
flutter run --dart-define-from-file=.env.json
```

---

## 🛡️ GitHub Safety Checklist

Before uploading the project, make sure these files and folders are not committed or manually uploaded:

- `.env.json`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`
- `build/`
- `.dart_tool/`
- `android/local.properties`
- `ios/Flutter/Generated.xcconfig`

This repository includes `.gitignore` rules for those paths, but manual drag-and-drop uploads to GitHub can still include ignored files. **Prefer using Git from the command line or GitHub Desktop.**

---

<div align="center">

Made with ❤️ by **Abhishek Wadhwani**

</div>
