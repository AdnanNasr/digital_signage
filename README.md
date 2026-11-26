# Raspberry Pi Digital Signage

نظام محلي لإدارة شاشة إعلانية، يُنفَّذ تدريجيًا. أُنجز التحكم بالمشغل وإدارة الفيديوهات الأساسية.
أُضيفت شاشة Flutter الألمانية **Übersicht** للتحكم بالمشغل. واجهة إدارة الفيديوهات والصور وقائمة التشغيل الدائمة والنشر مراحل لاحقة.

## المرحلة الأولى

- خادم FastAPI للتحكم بالمشغل عبر MPV JSON IPC مع مصادقة Bearer.
- عملية MPV واحدة؛ قفل للطلبات المتزامنة وقفل يمنع خادمين من إدارة المشغل نفسه.
- إعادة استخدام `get_videos` و`get_path` دون تعديل `python_project/main.py` المُجرَّب.
- ملء الشاشة، تكرار الفيديوهات وتعطيل الصوت كما في المشغل الأصلي.
- إيقاف الوسائط مع إبقاء نافذة MPV سوداء بواسطة `idle` و`force-window`.

```text
backend/app/config.py             # Environment configuration
backend/app/main.py               # App lifecycle and authentication
backend/app/routes/player.py      # Player endpoints
backend/app/services/player.py    # MPV process ownership and JSON IPC
backend/app/routes/media.py       # Video management endpoints
backend/app/services/media.py     # Video validation and storage
backend/tests/test_player_api.py
backend/tests/test_media_api.py
python_project/main.py            # Original player, unchanged
python_project/videos/            # Existing videos, reused by default
lib/models/player_status.dart     # Player response model and commands
lib/services/player_api.dart      # HTTP client
lib/providers/dashboard_provider.dart # Riverpod state and polling
lib/features/dashboard/dashboard_page.dart # Connection form and overview
```

## التشغيل على Raspberry Pi

لتنزيل المشروع كاملًا، بما فيه مجلد `python_project` والفيديو الموجود، من المستودع الخاص:

```bash
sudo apt update
sudo apt install git gh
gh auth login
gh repo clone AdnanNasr/digital_signage
cd digital_signage
```

لجلب التحديثات لاحقًا، نفّذ `git pull --ff-only` من داخل المشروع.
بيئة Python وملفات البناء والكاش لا تُرفع؛ تُنشأ على الجهاز باستخدام الخطوات التالية.

يلزم Python 3.11 أو أحدث وجلسة رسومية عاملة. نفّذ من جذر المشروع بحساب مستخدم الشاشة العادي:

```bash
sudo apt update
sudo apt install python3-venv mpv ffmpeg
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
backend/.venv/bin/python backend/run.py
```

عند غياب `SIGNAGE_API_TOKEN`، ينشئ الخادم رمزًا آمنًا تلقائيًا في `backend/runtime/api-token`
بصلاحيات `600` ويعيد استخدامه عند التشغيل التالي. مجلد `runtime` مستبعد من Git.
لتجربة الطلبات افتح Terminal ثانية في جذر المشروع:

```bash
export SIGNAGE_API_TOKEN="$(cat backend/runtime/api-token)"
```

يمكن تحديد رمز خاص عبر متغير البيئة؛ له الأولوية على الملف ويجب ألا يقل طوله عن 32 حرفًا.
إذا حددت `SIGNAGE_RUNTIME_DIR`، يُحفظ الملف في ذلك المجلد.
لا تشغّل `python_project/main.py` بالتزامن مع الخادم؛ فهو مشغل مستقل عن إدارة الـAPI.
لا تستخدم `--reload` أو أكثر من worker للشاشة. القفل يمنع خادمين يستخدمان مجلد التشغيل نفسه.

### إعداد التشغيل في IDE

اختر `backend/run.py` ملف التشغيل و`backend/.venv/bin/python` مفسّر Python.
لا يلزم تعيين رمز يدويًا؛ ملف التشغيل يحدد جذر المشروع تلقائيًا، حتى لو اختلف مجلد العمل.
يمكن اختيار منفذ آخر بإضافة `--port 8001`.

عند استخدام إعداد Uvicorn أو FastAPI في IDE، عيّن التطبيق إلى `backend.app.main:app`
ومجلد العمل إلى جذر `digital_signage`، وعطّل reload.
الأمر المكافئ من جذر المشروع:

```bash
backend/.venv/bin/python -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --workers 1
```

الخطأ `attempted relative import with no known parent package` يحدث عند تحميل
`backend/app/main.py` باسم مستقل مثل `main:app` أو كملف مباشر؛ الاستيرادات النسبية فيه تحتاج اسم الحزمة الكامل.
إذا كان خادم سابق يستخدم المنفذ، أوقفه بـ`Ctrl+C` قبل التشغيل مجددًا.

| المتغير | الافتراضي | الغرض |
|---|---|---|
| `SIGNAGE_API_TOKEN` | رمز محلي يُنشأ تلقائيًا | رمز وصول مخصص اختياري |
| `SIGNAGE_VIDEOS_DIR` | `python_project/videos` | مجلد الفيديوهات |
| `SIGNAGE_RUNTIME_DIR` | `backend/runtime` | مجلد خاص لمقبس IPC والقفل |
| `SIGNAGE_MPV_BINARY` | `mpv` | الملف التنفيذي |
| `SIGNAGE_MAX_UPLOAD_MB` | `512` | الحد الأقصى للفيديو المرفوع بالميبيبايت (MiB) |
| `SIGNAGE_FFPROBE_BINARY` | `ffprobe` | أداة فحص الفيديو، تأتي مع FFmpeg |
| `SIGNAGE_ALLOWED_ORIGINS` | `http://localhost:8080,http://127.0.0.1:8080` | مصادر الواجهة المسموح بها، مفصولة بفاصلة |

استخدم مسارًا قصيرًا لمجلد التشغيل بسبب حد طول Unix sockets.
ترتيب الفيديوهات أبجدي حسب الدالة الأصلية؛ الصيغ MP4 وMKV وMOV وWebM.
تُستبعد الروابط الرمزية التي تشير خارج مجلد الفيديوهات.

## تجربة API

```bash
curl http://127.0.0.1:8000/api/health
curl -H "Authorization: Bearer $SIGNAGE_API_TOKEN" http://127.0.0.1:8000/api/player/status
curl -X POST -H "Authorization: Bearer $SIGNAGE_API_TOKEN" http://127.0.0.1:8000/api/player/start
```

| الطريقة | المسار | الوظيفة |
|---|---|---|
| GET | `/api/health` | صحة الخادم، دون مصادقة |
| GET | `/api/player/status` | الحالة والملف الحالي وعدد الفيديوهات |
| POST | `/api/player/start` | بدء الفيديوهات أو استئناف العرض الحالي دون إعادة تحميله |
| POST | `/api/player/pause` | إيقاف مؤقت |
| POST | `/api/player/resume` | استئناف |
| POST | `/api/player/stop` | إيقاف الوسائط وإبقاء نافذة سوداء |
| POST | `/api/player/next` | التالي |
| POST | `/api/player/previous` | السابق |
| POST | `/api/player/restart` | إعادة تشغيل MPV والفيديوهات من البداية |

مثال للحالة:

```json
{"state":"playing","label":"Wird wiedergegeben","reachable":true,"current_file":"werbefilm 1 2.mp4","video_count":1}
```

قيم `state`: `playing`, `paused`, `stopped`, `unreachable`, `error` مع تسمية ألمانية في `label`.
`reachable` يصف اتصال MPV؛ قبل تشغيله تكون الحالة `stopped` مع `reachable: false`.
يعيد الخادم `401` للمصادقة، و`409` لغياب الفيديوهات أو التحكم بعرض غير نشط، و`503` لتعذر تشغيل MPV أو الاتصال به.

إغلاق المتصفح لا يوقف العرض. إيقاف خادم API نفسه ينهي MPV الذي يملكه.
إذا تعطلت MPV يظهر ذلك في الحالة، وطلب `start` التالي يعيد تشغيلها. الاستعادة التلقائية عبر systemd في مرحلة النشر.
الخادم مربوط حاليًا بـloopback؛ الوصول المحلي وHTTPS عبر Nginx يُجهَّزان في مرحلة النشر، دون تعريض النظام للإنترنت.

## واجهة Flutter — Übersicht

الواجهة تستخدم Material 3 وRiverpod وHTTP، مع تعريب مكونات Flutter إلى الألمانية.
تعرض اتصال الخادم، حالة المشغل، الملف الحالي وعدد الفيديوهات، وتدعم أوامر التشغيل السبعة.
تتحدث الحالة كل خمس ثوانٍ، وتُعطَّل الأوامر عند انقطاع الاتصال أو أثناء الطلب الجاري.
رمز الوصول يبقى في ذاكرة الجلسة فقط؛ لا يُحفظ في المتصفح ولا يُضمَّن داخل ملفات البناء.
تسجيل الخروج أو إغلاق الصفحة لا يوقف MPV.

للتجربة على الـMac، شغّل الخادم في Terminal أولى:

```bash
backend/.venv/bin/python backend/run.py
```

في Terminal ثانية من جذر المشروع:

```bash
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 --no-web-resources-cdn
```

الواجهة على `http://127.0.0.1:8080`، والخادم على `http://127.0.0.1:8000`.
في شاشة الاتصال استخدم عنوان الخادم، والصق المفتاح من الملف المحلي:

```bash
cat backend/runtime/api-token
```

إذا عيّنت `SIGNAGE_API_TOKEN` يدويًا، استخدم تلك القيمة بدل الملف.
إذا غيّرت منفذ الواجهة، أضف مصدرها الكامل إلى `SIGNAGE_ALLOWED_ORIGINS` ثم أعد تشغيل الخادم.
لم يُفتح الخادم لأجهزة الشبكة الأخرى بعد؛ إعداد Nginx سيكون في مرحلة النشر.

لبناء نسخة بموارد محلية قابلة للاستضافة لاحقًا دون CDN:

```bash
flutter build web --release --no-web-resources-cdn
```

عند عدم تحديد `API_BASE_URL`، تقترح الواجهة عنوان استضافتها نفسه للـAPI، ليناسب Nginx لاحقًا.
لا تضع رمز الوصول في `--dart-define`؛ أدخله في شاشة الاتصال.

للتحقق من الواجهة:

```bash
flutter analyze
flutter test
```

تغطي الاختبارات الدخول، الأوامر السبعة، المفاتيح غير الصحيحة، انقطاع الاتصال والتعافي،
تعطيل التشغيل عند غياب الفيديوهات، والتخطيط على شاشة بعرض 320 بكسل.
شاشة **Medien** ستكون الخطوة التالية؛ وظائفها متاحة حاليًا عبر API فقط.

## إدارة الفيديوهات

تستخدم المجلد نفسه دون قاعدة بيانات؛ اسم الملف هو معرّفه. جميع الطلبات تحتاج رمز الوصول.

| الطريقة | المسار | الوظيفة |
|---|---|---|
| GET | `/api/media` | قائمة الفيديوهات مع الاسم والحجم بالبايت |
| GET | `/api/media/{id}` | معلومات فيديو محدد |
| POST | `/api/media/upload?filename=clip.mp4` | رفع فيديو |
| DELETE | `/api/media/{id}?confirm=true` | حذف بعد التأكيد |

الرفع يرسل بايتات الملف مباشرة في جسم الطلب، **دون multipart**، واسم الملف في query parameter.
هذا يسمح بالكتابة التدريجية وحد الحجم دون مكتبة إضافية؛ يمكن للواجهة رفع عدة ملفات بطلب مستقل لكل ملف.
أمثلة من Terminal ثانية بعد بدء الخادم:

```bash
export SIGNAGE_API_TOKEN="$(cat backend/runtime/api-token)"
curl -H "Authorization: Bearer $SIGNAGE_API_TOKEN" http://127.0.0.1:8000/api/media
curl -X POST -H "Authorization: Bearer $SIGNAGE_API_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@/path/to/clip.mp4" \
  "http://127.0.0.1:8000/api/media/upload?filename=clip.mp4"
```

استبدل مسار المثال بمسار الفيديو لديك. استجابة الرفع الناجح `201` ومعلومات الملف.
يُرفض الاسم الموجود بـ`409` دون استبداله، والمسارات غير الآمنة بـ`400`، والامتداد غير المدعوم بـ`415`،
والملف الفارغ أو المزيف أو الصوتي فقط بـ`422`، وتجاوز الحجم بـ`413`، وغياب FFprobe بـ`503`، وامتلاء القرص بـ`507`.
الحد مطبق أثناء استقبال البيانات أيضًا، حتى عند غياب `Content-Length`.
يفحص FFprobe الحاوية ووجود مسار فيديو؛ لا يجري تحويلًا أو فك ترميز كامل لكل إطار.
يُكتب الملف مؤقتًا ولا يراه المشغل إلا بعد اكتمال الرفع ونجاح الفحص. الرفع المنقطع ينظَّف تلقائيًا.

للحذف، أوقف العرض إذا كان الفيديو ضمن القائمة المحملة، ثم أكّد الحذف:

```bash
curl -X POST -H "Authorization: Bearer $SIGNAGE_API_TOKEN" http://127.0.0.1:8000/api/player/stop
curl -X DELETE -H "Authorization: Bearer $SIGNAGE_API_TOKEN" \
  "http://127.0.0.1:8000/api/media/clip.mp4?confirm=true"
```

الحذف الناجح يعيد `204` دون محتوى. حماية القائمة تشمل الفيديو الحالي والمتوقف مؤقتًا والملفات المنتظرة؛
طلب دون `confirm=true` يعيد `400`. ستعرض واجهة Flutter نافذة التأكيد لاحقًا.
الفيديوهات الجديدة تدخل العرض عند بدء قائمة جديدة أو إعادة تشغيل المشغل؛ الرفع لا يقطع العرض الجاري.

## الاختبارات

```bash
sudo apt install ffmpeg
backend/.venv/bin/python -m pip install -r backend/requirements-dev.txt
backend/.venv/bin/python -m unittest discover -s backend/tests -v
```

اختبارات التكامل تتطلب `mpv` و`ffmpeg`؛ بدونهما تظهر كتجاوزات. تُنشئ فيديوهات مؤقتة وتستخدم MPV دون نافذة أو صوت، ثم تنظف العمليات والملفات.
تشمل المصادقة والتشغيل والتنقل والإيقاف والاستئناف وإعادة التشغيل والتعافي بعد التعطل وطلبات التشغيل المتزامنة.
تشمل إدارة الفيديوهات الصيغ الأربع، الملفات المزيفة والصوتية، حدود الحجم والرفع المنقطع،
والأسماء غير الآمنة والروابط الرمزية، ومنع الحذف أثناء التشغيل ومنع الاستبدال عند الرفع المتزامن.

نجحت الاختبارات محليًا على macOS. لم يُختبر الخادم الجديد على Raspberry Pi بعد؛ قبل اعتماد المرحلة على الجهاز:

1. جرّب جميع أوامر الجدول وتأكد من ملء الشاشة وغياب الصوت.
2. تحقق بصريًا من بقاء شاشة سوداء عند `stop`.
3. تحقق من تكرار الفيديوهات واستمرارها بعد إغلاق المتصفح.
4. إذا لم تظهر النافذة شغّل الخادم من جلسة الشاشة نفسها وافحص `DISPLAY` أو `WAYLAND_DISPLAY` وصلاحيات المستخدم، دون تشغيله باستخدام root.

مراجع: [MPV وخيارات JSON IPC](https://mpv.io/manual/stable/)، [FastAPI lifespan](https://fastapi.tiangolo.com/advanced/events/)، [اختبار دورة حياة الخادم](https://fastapi.tiangolo.com/advanced/testing-events/).
الرفع التدريجي موضح في [Starlette Requests](https://starlette.dev/requests/)، وفحص المسارات في [FFprobe](https://ffmpeg.org/ffprobe.html).
إعداد اتصال المتصفح في [FastAPI CORS](https://fastapi.tiangolo.com/tutorial/cors/)، وإدارة الموارد في [Riverpod Refs](https://riverpod.dev/docs/concepts2/refs).
