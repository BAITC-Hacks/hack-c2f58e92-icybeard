from pathlib import Path

from fastapi.testclient import TestClient

from darumen.scribe.app import create_app
from darumen.scribe.draft import RuleDrafter
from darumen.scribe.store import SessionStore
from darumen.scribe.transcribe import FakeTranscriber


def client(tmp_path: Path) -> tuple[TestClient, SessionStore]:
    store = SessionStore(tmp_path / "scribe")
    return TestClient(create_app(store, FakeTranscriber(), RuleDrafter())), store


def test_consent_is_required(tmp_path):
    api, _ = client(tmp_path)
    assert api.post("/scribe/sessions", json={"consent": False}).status_code == 400
    assert api.post("/scribe/sessions", json={"consent": True, "language": "de"}).status_code == 422


def test_full_flow_audio_draft_approve_leaflet_and_audio_deleted(tmp_path):
    api, store = client(tmp_path)
    created = api.post("/scribe/sessions", json={"consent": True, "language": "ru"}, headers={"X-Actor": "doctor1"})
    assert created.status_code == 201
    session_id = created.json()["sessionId"]

    uploaded = api.post(f"/scribe/sessions/{session_id}/audio", files={"file": ("consult.webm", b"\x1a\x45\xdf\xa3fake-audio", "audio/webm")})
    assert uploaded.status_code == 200
    assert "амлодипин" in uploaded.json()["text"]
    audio_files = list((store.root / "audio").iterdir())
    assert len(audio_files) == 1

    draft = api.post(f"/scribe/sessions/{session_id}/draft").json()
    names = [s["name"] for s in draft["sections"]]
    assert "Жалобы" in names and "Осмотр" in names and "Диагноз" in names and "Назначения" in names
    assert "амлодипин" in draft["patientLeaflet"]["text"] and draft["model"] == "rules@1.0.0"

    approved = api.post(f"/scribe/sessions/{session_id}/approve", json={"sections": draft["sections"], "patientLeaflet": draft["patientLeaflet"]["text"] + " Явка через 2 недели."})
    assert approved.status_code == 200
    token = approved.json()["leafletToken"]
    assert not list((store.root / "audio").iterdir())  # аудио удалено при утверждении
    assert api.post(f"/scribe/sessions/{session_id}/audio", files={"file": ("x.webm", b"1", "audio/webm")}).status_code == 409
    # утверждённую запись нельзя пересобрать или утвердить повторно с другой памяткой
    assert api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Новый текст."}).status_code == 409
    assert api.post(f"/scribe/sessions/{session_id}/draft").status_code == 409
    assert api.post(f"/scribe/sessions/{session_id}/approve", json={"sections": draft["sections"], "patientLeaflet": "другая"}).status_code == 409

    leaflet = api.get(f"/scribe/leaflets/{token}").json()
    assert "Явка через 2 недели" in leaflet["text"] and leaflet["language"] == "ru"
    assert api.get("/scribe/leaflets/nope").status_code == 404


def test_typed_transcript_without_microphone(tmp_path):
    api, _ = client(tmp_path)
    session_id = api.post("/scribe/sessions", json={"consent": True}).json()["sessionId"]
    assert api.post(f"/scribe/sessions/{session_id}/draft").status_code == 409
    api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Жалобы на кашель неделю. Температура 37.5. Назначаю обильное питьё и контроль через три дня."})
    draft = api.post(f"/scribe/sessions/{session_id}/draft").json()
    assert any(s["name"] == "Назначения" and "контроль" in s["text"] for s in draft["sections"])
    assert api.get("/scribe/health").json()["transcriber"] == "fake"


def test_llm_drafter_without_key_uses_rules(monkeypatch):
    from darumen.scribe.draft import LlmDrafter
    from darumen.scribe.transcribe import Segment

    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)
    monkeypatch.delenv("DARUMEN_LLM_PROVIDER", raising=False)
    drafter = LlmDrafter(provider="deepseek")
    assert drafter.name == "deepseek/deepseek-chat" and not drafter.available()
    draft = drafter.draft([Segment(0, 4, "Жалобы на кашель. Назначаю сироп.")], "ru")
    assert draft.model == "rules@1.0.0" and any(s.name == "Назначения" for s in draft.sections)
    local = LlmDrafter()
    assert local.name == "ollama/darumen-qwen3.8:27b" and local.available()
    assert LlmDrafter.THINK.sub("", "<think>мысли</think>{\"a\": 1}") == '{"a": 1}'


class _FakeMessage:
    def __init__(self, content: str):
        self.content = content


class _FakeChoice:
    def __init__(self, content: str):
        self.message = _FakeMessage(content)


class _FakeCompletion:
    def __init__(self, content: str):
        self.choices = [_FakeChoice(content)]


class _FakeCompletions:
    def __init__(self, content: str):
        self._content = content

    def create(self, **kwargs):
        return _FakeCompletion(self._content)


class _FakeChat:
    def __init__(self, content: str):
        self.completions = _FakeCompletions(content)


class _FakeOpenAI:
    """Мок openai.OpenAI: конструктор игнорирует аргументы, chat.completions.create отдаёт заранее заданный JSON."""

    _next_content: str = "{}"

    def __init__(self, *args, **kwargs):
        self.chat = _FakeChat(self._next_content)


def _mock_llm_response(monkeypatch, content: str):
    _FakeOpenAI._next_content = content
    monkeypatch.setattr("openai.OpenAI", _FakeOpenAI)


def _drafter_segments():
    from darumen.scribe.transcribe import Segment

    return [
        Segment(0, 4, "Жалуется на кашель."),
        Segment(4, 8, "Назначаю сироп от кашля."),
    ]


def test_llm_drafter_populates_spans_from_cited_segment_indices(monkeypatch):
    from darumen.scribe.draft import LlmDrafter

    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-key")
    _mock_llm_response(
        monkeypatch,
        '{"sections": {"Жалобы": {"text": "Кашель.", "segments": [0]}, "Анамнез": {"text": "", "segments": []}, '
        '"Осмотр": {"text": "", "segments": []}, "Диагноз": {"text": "", "segments": []}, '
        '"Назначения": {"text": "Сироп от кашля.", "segments": [1]}}, "leaflet": "Принимайте сироп."}',
    )
    drafter = LlmDrafter(provider="deepseek")
    draft = drafter.draft(_drafter_segments(), "ru")

    assert draft.model == "deepseek/deepseek-chat"
    by_name = {s.name: s for s in draft.sections}
    assert by_name["Жалобы"].spans == [{"t0": 0, "t1": 4}]
    assert by_name["Назначения"].spans == [{"t0": 4, "t1": 8}]


def test_llm_drafter_drops_out_of_range_or_malformed_segment_indices(monkeypatch):
    from darumen.scribe.draft import LlmDrafter

    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-key")
    _mock_llm_response(
        monkeypatch,
        '{"sections": {"Жалобы": {"text": "Кашель.", "segments": [0, 7, "оops", null, true]}, "Анамнез": {"text": "", "segments": []}, '
        '"Осмотр": {"text": "", "segments": []}, "Диагноз": {"text": "", "segments": []}, '
        '"Назначения": {"text": "", "segments": []}}, "leaflet": "Памятка."}',
    )
    drafter = LlmDrafter(provider="deepseek")
    draft = drafter.draft(_drafter_segments(), "ru")

    by_name = {s.name: s for s in draft.sections}
    # индекс 7 не существует, "оops"/null/true — не валидные индексы: отбрасываются, а не роняют черновик
    assert by_name["Жалобы"].spans == [{"t0": 0, "t1": 4}]


def test_llm_drafter_falls_back_to_empty_spans_for_old_plain_string_sections(monkeypatch):
    """Ответ старого/сломанного формата (раздел — просто строка, а не {text, segments}) не должен ронять черновик."""
    from darumen.scribe.draft import LlmDrafter

    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-key")
    _mock_llm_response(
        monkeypatch,
        '{"sections": {"Жалобы": "Кашель.", "Анамнез": "", "Осмотр": "", "Диагноз": "", "Назначения": ""}, '
        '"leaflet": "Памятка."}',
    )
    drafter = LlmDrafter(provider="deepseek")
    draft = drafter.draft(_drafter_segments(), "ru")

    assert draft.model == "deepseek/deepseek-chat"
    by_name = {s.name: s for s in draft.sections}
    assert by_name["Жалобы"].text == "Кашель." and by_name["Жалобы"].spans == []


class _Silent:
    name = "silent"
    state = "ready"
    error = None

    def transcribe(self, audio, language):
        return []


class _Loading:
    name = "loading"
    state = "loading"
    error = None

    def transcribe(self, audio, language):
        from darumen.scribe.transcribe import TranscriberUnavailable

        raise TranscriberUnavailable("модель распознавания речи ещё загружается")


class _Broken:
    name = "broken"
    state = "ready"
    error = None

    def transcribe(self, audio, language):
        raise ValueError("Invalid data found when processing input")


def _upload(api):
    session_id = api.post("/scribe/sessions", json={"consent": True, "language": "ru", "patientRef": "SYN-75-028B-381-03"}).json()["sessionId"]
    return session_id, api.post(f"/scribe/sessions/{session_id}/audio", files={"file": ("a.webm", b"\x1a\x45\xdf\xa3x", "audio/webm")})


def test_audio_errors_are_explained_and_audio_is_not_kept(tmp_path):
    for transcriber, status, words in ((_Silent(), 422, "речь не распознана"), (_Loading(), 503, "загружается"), (_Broken(), 422, "не удалось распознать запись")):
        store = SessionStore(tmp_path / transcriber.name)
        api = TestClient(create_app(store, transcriber, RuleDrafter()))
        _, response = _upload(api)
        assert response.status_code == status
        body = response.json()
        assert body["title"] == "Скрайб" and words in body["detail"]
        assert not list((store.root / "audio").iterdir())  # неудачная запись не остаётся на диске
    assert TestClient(create_app(SessionStore(tmp_path / "h"), _Loading(), RuleDrafter())).get("/scribe/health").json()["transcriberState"] == "loading"


def test_typed_transcript_splits_sentences_on_any_ending_and_keeps_decimals(tmp_path):
    api, _ = client(tmp_path)
    session_id = api.post("/scribe/sessions", json={"consent": True}).json()["sessionId"]
    result = api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Болит голова? Температура 37.5 два дня!\nНазначаю парацетамол 500 мг"}).json()
    assert [s["text"] for s in result["transcript"]] == ["Болит голова?", "Температура 37.5 два дня!", "Назначаю парацетамол 500 мг."]


def test_session_survives_a_restart_and_can_be_resumed(tmp_path):
    store = SessionStore(tmp_path / "scribe")
    api = TestClient(create_app(store, FakeTranscriber(), RuleDrafter()))
    session_id = api.post("/scribe/sessions", json={"consent": True, "patientRef": "SYN-75-028B-381-03"}).json()["sessionId"]
    api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Жалобы на кашель. Назначаю обильное питьё."})
    api.post(f"/scribe/sessions/{session_id}/draft")

    # новый процесс сервиса: сессия читается с диска, стенограмма и черновик на месте
    restarted = TestClient(create_app(SessionStore(tmp_path / "scribe"), FakeTranscriber(), RuleDrafter()))
    state = restarted.get(f"/scribe/sessions/{session_id}").json()
    assert state["approved"] is False and len(state["transcript"]) == 2
    assert state["draft"]["sections"] and state["draft"]["patientLeaflet"]["text"]
    assert restarted.get("/scribe/sessions/nope").status_code == 404


class _Corrector(RuleDrafter):
    """Черновик по правилам и исправление терминов без сети: правдоподобная и непохожая (пересказ) правки."""

    def __init__(self):
        self.terms = None

    def correct(self, texts, terms, language):
        self.terms = terms
        return {0: "Назначаю амлодипин 5 мг."}


def test_doctor_edits_a_phrase_and_can_revert_it(tmp_path):
    api, store = client(tmp_path)
    session_id = api.post("/scribe/sessions", json={"consent": True}).json()["sessionId"]
    api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Назначаю амла дипин 5 мг. Контроль через неделю."})

    edited = api.post(f"/scribe/sessions/{session_id}/segments/0", json={"text": "Назначаю амлодипин 5 мг."}).json()["transcript"]
    assert edited[0] == {"t0": 0.0, "t1": 4.0, "text": "Назначаю амлодипин 5 мг.", "original": "Назначаю амла дипин 5 мг.", "source": "doctor"}
    assert "original" not in edited[1]
    assert SessionStore(store.root).get(session_id).transcript[0]["source"] == "doctor"  # правка сохранена на диск

    reverted = api.post(f"/scribe/sessions/{session_id}/segments/0", json={"text": "Назначаю амла дипин 5 мг."}).json()["transcript"]
    assert reverted[0] == {"t0": 0.0, "t1": 4.0, "text": "Назначаю амла дипин 5 мг."}
    assert api.post(f"/scribe/sessions/{session_id}/segments/9", json={"text": "x"}).status_code == 404


def test_ai_correction_marks_fixed_phrases_and_uses_dictionary_candidates(tmp_path):
    from darumen.scribe.vocabulary import Vocabulary

    corrector, vocab = _Corrector(), Vocabulary(tmp_path / "scribe")
    api = TestClient(create_app(SessionStore(tmp_path / "scribe"), FakeTranscriber(), corrector, vocab))
    session_id = api.post("/scribe/sessions", json={"consent": True}).json()["sessionId"]
    assert api.post(f"/scribe/sessions/{session_id}/correct").status_code == 409
    api.post(f"/scribe/sessions/{session_id}/transcript", json={"text": "Назначаю амладипин 5 мг. Гипертоническая болесь."})

    result = api.post(f"/scribe/sessions/{session_id}/correct").json()
    assert result["changed"] == 1
    assert result["transcript"][0] == {"t0": 0.0, "t1": 4.0, "text": "Назначаю амлодипин 5 мг.", "original": "Назначаю амладипин 5 мг.", "source": "ai"}
    assert "амлодипин" in corrector.terms and "гипертоническая болезнь" in corrector.terms

    # без языковой модели исправляет словарь и честно говорит, что ИИ недоступен
    plain = TestClient(create_app(SessionStore(tmp_path / "other"), FakeTranscriber(), RuleDrafter()))
    sid = plain.post("/scribe/sessions", json={"consent": True}).json()["sessionId"]
    plain.post(f"/scribe/sessions/{sid}/transcript", json={"text": "Диагноз острый бронхит. Назначаю амоксицелин."})
    fixed = plain.post(f"/scribe/sessions/{sid}/correct").json()
    assert fixed["changed"] == 1 and fixed["aiError"]
    assert fixed["transcript"][1] == {"t0": 4.0, "t1": 8.0, "text": "Назначаю амоксициллин.", "original": "Назначаю амоксицелин.", "source": "dictionary"}


def test_dictionary_fixes_misspelled_terms_but_keeps_word_endings():
    from darumen.scribe.vocabulary import Vocabulary

    v = Vocabulary()
    fixes = v.fix_by_dictionary(["Назначаю амоксицелин и метаформин.", "Острого бронхита и гипертонической болезни нет.", "Пациент пришёл утром."], "ru")
    assert fixes == {0: "Назначаю амоксициллин и метформин."}
    groups = v.builtin_groups()
    assert any(g["name"] == "Лекарства" and "амлодипин" in g["terms"] for g in groups)
    assert sum(len(g["terms"]) for g in groups) == v.builtin_count()


def test_llm_correction_keeps_only_plausible_fixes(monkeypatch):
    from darumen.scribe.draft import LlmDrafter, plausible_fix

    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-key")
    _mock_llm_response(monkeypatch, '{"segments": [{"i": 0, "text": "Назначаю амлодипин 5 мг."}, '
                                    '{"i": 1, "text": "Совершенно другой пересказ всего приёма врачом целиком"}, {"i": 7, "text": "x"}]}')
    fixes = LlmDrafter(provider="deepseek").correct(["Назначаю амладипин 5 мг.", "Контроль через неделю."], ["амлодипин"], "ru")
    assert fixes == {0: "Назначаю амлодипин 5 мг."}
    assert plausible_fix("гипертоническая болесь", "гипертоническая болезнь")
    assert not plausible_fix("Контроль через неделю.", "Пациент здоров, наблюдение не требуется, всё хорошо.")


def test_clinic_vocabulary_is_saved_and_goes_into_the_speech_prompt(tmp_path):
    from darumen.scribe.vocabulary import Vocabulary

    api = TestClient(create_app(SessionStore(tmp_path / "scribe"), FakeTranscriber(), RuleDrafter(), Vocabulary(tmp_path / "scribe")))
    assert api.get("/scribe/vocabulary").json()["builtIn"] > 300
    saved = api.post("/scribe/vocabulary", json={"words": [" Нолипрел ", "нолипрел", "", "Конкор"]}).json()
    assert saved["words"] == ["Нолипрел", "Конкор"]

    again = Vocabulary(tmp_path / "scribe")  # после перезапуска
    assert again.custom == ["Нолипрел", "Конкор"]
    assert "Нолипрел" in again.prompt("ru") and len(again.prompt("ru")) <= 600
    assert "амлодипин" in again.candidates(["назначаю амладипин"], "ru")
