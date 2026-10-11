# 기술 설계서 (TECH) v0.1

> 작성: 팀장(Opus) · 엔진 **Godot 4.6 stable** · 언어 **정적 타입 GDScript**

## 1. 엔진 선정 근거 (Three.js 대비)

"사용자가 직접 작업하지 않는다"는 전제로 검증했다 (2026-10-09, 이 클라우드 환경에서 실측).

| 항목 | Godot 4.6 | Three.js |
|---|---|---|
| 이 환경에서 렌더링 검증 | ✅ Forward+ 렌더러 동작 확인 (lavapipe 소프트웨어 Vulkan + Xvfb). 그림자, SDFGI 전역조명, 볼류메트릭 포그, SSR까지 스크린샷 생성 | ✅ WebGL2 동작 (SwiftShader). WebGPU 불가 |
| 오픈월드 기능 | 내장: 자동 메시 LOD, 가시 거리(HLOD), 오클루전 컬링, 내비메시, Jolt 물리, GPU 파티클, AnimationTree(상태머신·블렌드 스페이스·루트모션) | 대부분 직접 구현해야 함 |
| 그래픽 상한 | 높음 (전역조명, 볼류메트릭 포그 내장) | 중간 (후처리로 보완) |
| 상업 출시 | Windows/Mac/Linux 네이티브 빌드 → Steam. MIT 라이선스, 로열티 없음 | 웹 기본. 데스크톱은 래퍼 필요, 대형 월드 성능 불리 |
| AI 편집 가능성 | 씬(.tscn), 리소스(.tres), 스크립트 전부 텍스트 | 전부 코드 |

**결론: Godot 4.6.** 단점은 두 가지다. (1) 플레이하려면 실행 파일을 받아야 한다. 웹 데모는 저사양 렌더러로 따로 뽑을 수 있다. (2) 이 환경은 GPU가 없어서 실시간 FPS 측정은 근사치만 가능하다.

## 2. 개발 환경 (세션마다 자동 구성)
- `tools/setup_env.sh`: `mesa-vulkan-drivers`(lavapipe)를 설치하고 Godot 4.6 바이너리를 `tools/bin/`에 받는다 (git 제외).
- 클라우드 세션 시작 훅(SessionStart)에 연결해 새 세션에서도 바로 실행되게 한다.
- 실행 모드:
  - 로직 테스트: `godot --headless` (렌더링 없음, 빠름)
  - 화면 검증: `xvfb-run` + `VK_ICD_FILENAMES=lvp_icd.json` → 스크린샷과 짧은 영상(`--write-movie`)

## 3. 백엔드/프론트엔드 분리 원칙
모든 액터(플레이어, 적, NPC, 오브젝트)는 다음 구조를 따른다.

```
Actor (CharacterBody3D) ← 로직: 스크립트, 컴포넌트, 상태머신
├── Components/        ← Health, Stamina, Poise, Hitbox, Hurtbox, BoonHolder …
├── StateMachine/
├── CollisionShape3D
└── Visual (Node3D)    ← ★ 프론트엔드 교체 지점
                          Phase 2: 회색 캡슐/박스
                          Phase 4: 모델 + AnimationTree + VFX
```
- **로직은 Visual을 참조하지 않는다.** Visual이 로직의 시그널(`attacked`, `damaged`, `state_changed`)을 구독해서 표현만 한다.
- **공격 타이밍은 데이터로 정의한다.** 선딜, 판정, 후딜 프레임을 데이터에 두고 히트박스를 켜고 끈다. Phase 4에서는 애니메이션을 이 프레임 데이터에 맞춘다. 그래서 그래픽이 바뀌어도 전투 밸런스는 그대로다.

## 4. 폴더 구조
```
project.godot
game/
  core/        순수 로직 (RefCounted, 노드 비의존): 데미지 공식, 스탯, 인벤토리, 퀘스트 상태, 세이브 데이터
  components/  재사용 노드 컴포넌트: health, stamina, poise, hitbox, hurtbox, lock_on_target …
  actors/      player/, enemies/, bosses/, npcs/  (씬 + 스크립트)
  ai/          상태머신, 공격 선택기, 보스 페이즈
  systems/     오토로드: GameState, EventBus, SaveManager, QuestManager, DialogueManager, WorldStreamer
  world/       지역 씬, 청크, 화로, 상호작용 오브젝트
  ui/          (Phase 2: 디버그 HUD만 / Phase 4: 정식 UI)
data/          콘텐츠 정의 JSON: items, weapons, enemies, boons, quests, dialogue
localization/  strings.csv (key, ko, en)
assets/        (Phase 4) models, textures, audio, shaders
tests/         unit/, scenario/, visual/
tools/         setup_env.sh, run_tests.sh, validate_data.py, screenshot.sh
docs/
```

## 5. 핵심 기술 결정
| 영역 | 결정 | 이유 |
|---|---|---|
| 물리 | Jolt (Godot 4.6 내장), 액터는 `CharacterBody3D` | 안정성, 성능 |
| 콘텐츠 데이터 | `data/*.json`을 시작 시 타입 Resource로 로드, 스키마는 `tools/validate_data.py`로 검증 | LLM이 생성·변환하기 쉽고 검증이 자동화됨 (Haiku 담당) |
| 다국어 | `localization/strings.csv` (key, ko, en) → Godot TranslationServer | 텍스트는 키로만 참조. 번역은 Haiku |
| 적 AI | 계층형 상태머신 + 가중치 기반 공격 선택 (거리, 각도, 쿨다운) | 소울라이크 적에 적합하고 디버깅이 쉬움. 외부 애드온 의존 없음 |
| 대화 | 자체 JSON 대화 그래프 (노드: 대사, 선택지, 조건, 이벤트) | 퀘스트 시스템과 직접 연동 |
| 퀘스트 | 단계 기반 상태머신 + 이벤트 버스 트리거 (`enemy_killed`, `item_acquired`, `area_entered` 등) | 데이터 기반, 테스트 용이 |
| 세이브 | `user://saves/*.json`, 버전 필드와 마이그레이션 함수 | 업데이트 후에도 세이브 호환 |
| 월드 | 128m 청크 그리드, 플레이어 거리 기반 비동기 로드/언로드 + 가시 거리 LOD | 1km² 이상 확장 대비 |
| 지형 | Phase 2는 노이즈 하이트맵 메시 + HeightMapShape3D. Phase 4에서 Terrain3D(MIT) 도입 검토 | 그레이박스에서 시작해 점진 교체 |
| 입력 | InputMap 액션 (키보드·마우스 + 게임패드), 선입력 버퍼 0.2초 | 소울라이크 조작감 |
| 테스트 | 헤드리스 유닛 테스트 + 시나리오 테스트(입력 시뮬레이션) + 시각 테스트(스크린샷) | 팀원 결과물을 테스트로 검증 |

## 6. 코딩 규칙 (팀원 공통)
- 모든 변수와 함수에 **정적 타입**을 쓴다. `untyped_declaration` 경고는 에러로 처리한다.
- 파일과 변수는 snake_case, 클래스는 PascalCase + `class_name`, 시그널은 과거형(`damaged`, `died`)으로 짓는다.
- 시스템 간 통신은 `EventBus` 시그널로만 한다. 다른 시스템의 내부를 직접 참조하지 않는다.
- 하드코딩 금지: 수치는 `data/`, 문자열은 `localization/`에 둔다.
- 새 기능에는 테스트를 하나 이상 붙인다. PR 단위 대신 작업 단위로 커밋한다.
