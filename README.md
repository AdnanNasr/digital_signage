# Raspberry Pi Digital Signage

نظام محلي لإدارة شاشة إعلانية، يُنفَّذ تدريجيًا. المرحلة الحالية: **Backend und Player**.
تطبيق Flutter ما زال القالب الأولي؛ إدارة الوسائط والواجهة وقائمة التشغيل الدائمة والنشر مراحل لاحقة.

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
backend/tests/test_player_api.py
python_project/main.py            # Original player, unchanged
python_project/videos/            # Existing videos, reused by default
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
sudo apt install python3-venv mpv
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

## الاختبارات

```bash
sudo apt install ffmpeg
backend/.venv/bin/python -m pip install -r backend/requirements-dev.txt
backend/.venv/bin/python -m unittest discover -s backend/tests -v
```

اختبارات التكامل تتطلب `mpv` و`ffmpeg`؛ بدونهما تظهر كتجاوزات. تُنشئ فيديوهات مؤقتة وتستخدم MPV دون نافذة أو صوت، ثم تنظف العمليات والملفات.
تشمل المصادقة والتشغيل والتنقل والإيقاف والاستئناف وإعادة التشغيل والتعافي بعد التعطل وطلبات التشغيل المتزامنة.

نجحت الاختبارات محليًا على macOS. لم يُختبر الخادم الجديد على Raspberry Pi بعد؛ قبل اعتماد المرحلة على الجهاز:

1. جرّب جميع أوامر الجدول وتأكد من ملء الشاشة وغياب الصوت.
2. تحقق بصريًا من بقاء شاشة سوداء عند `stop`.
3. تحقق من تكرار الفيديوهات واستمرارها بعد إغلاق المتصفح.
4. إذا لم تظهر النافذة شغّل الخادم من جلسة الشاشة نفسها وافحص `DISPLAY` أو `WAYLAND_DISPLAY` وصلاحيات المستخدم، دون تشغيله باستخدام root.

مراجع: [MPV وخيارات JSON IPC](https://mpv.io/manual/stable/)، [FastAPI lifespan](https://fastapi.tiangolo.com/advanced/events/)، [اختبار دورة حياة الخادم](https://fastapi.tiangolo.com/advanced/testing-events/).
