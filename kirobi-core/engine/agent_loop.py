"""
kirobi-core/engine/agent_loop.py
Kirobi Autonomous AI Orchestrator — AgentLoop mit 4-Quadranten-Engine

Kernkomponenten:
  - Task:                  Datenklasse für eine Aufgabe
  - QuadrantClassifier:    Eisenhower-Matrix Klassifizierung
  - KirobiBrain:           Schnittstelle zu Ollama (lokalem LLM)
  - AgentLoop:             Haupt-Verarbeitungsschleife
  - SelfImprovementLoop:   Performance-Analyse und Optimierung
  - HermesAgent:           Kommunikation und Benachrichtigungen

Verwendung:
  python3 agent_loop.py
  python3 agent_loop.py --config /path/to/config.yaml
  python3 agent_loop.py --task "Analysiere meine Projekte"
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import time
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum, auto
from pathlib import Path
from typing import Any, Optional

import httpx
import yaml

# ============================================================
# LOGGING KONFIGURATION
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
    ],
)

logger = logging.getLogger("kirobi")


# ============================================================
# ENUMERATIONEN
# ============================================================

class Quadrant(Enum):
    """Eisenhower-Matrix Quadranten."""
    Q1_WICHTIG_DRINGEND = 1      # Sofort erledigen
    Q2_WICHTIG_NICHT_DRINGEND = 2  # Planen
    Q3_DRINGEND_NICHT_WICHTIG = 3  # Delegieren
    Q4_WEDER_NOCH = 4             # Eliminieren


class TaskStatus(Enum):
    """Status einer Aufgabe."""
    PENDING = auto()    # Wartet auf Verarbeitung
    RUNNING = auto()    # Wird gerade verarbeitet
    COMPLETED = auto()  # Erfolgreich abgeschlossen
    FAILED = auto()     # Fehlgeschlagen
    CANCELLED = auto()  # Abgebrochen


class TaskPriority(Enum):
    """Priorität einer Aufgabe (absteigend)."""
    CRITICAL = 0
    HIGH = 1
    MEDIUM = 2
    LOW = 3


# ============================================================
# DATENKLASSEN
# ============================================================

@dataclass
class Task:
    """Repräsentiert eine einzelne Aufgabe im Kirobi-System."""

    # Pflichtfelder
    description: str

    # Automatisch generierte Felder
    id: str = field(default_factory=lambda: str(uuid.uuid4())[:8])
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    # Klassifizierung (wird vom QuadrantClassifier gesetzt)
    quadrant: Optional[Quadrant] = None
    priority: TaskPriority = TaskPriority.MEDIUM
    importance_score: float = 0.5  # 0.0 bis 1.0
    urgency_score: float = 0.5     # 0.0 bis 1.0

    # Status-Tracking
    status: TaskStatus = TaskStatus.PENDING
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    attempts: int = 0
    max_attempts: int = 3

    # Ergebnis
    result: Optional[str] = None
    error: Optional[str] = None

    # Kontext
    context: dict[str, Any] = field(default_factory=dict)
    tags: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Quadranten-Priorität aus Quadrant ableiten."""
        if self.quadrant is not None:
            priority_map = {
                Quadrant.Q1_WICHTIG_DRINGEND: TaskPriority.CRITICAL,
                Quadrant.Q2_WICHTIG_NICHT_DRINGEND: TaskPriority.HIGH,
                Quadrant.Q3_DRINGEND_NICHT_WICHTIG: TaskPriority.MEDIUM,
                Quadrant.Q4_WEDER_NOCH: TaskPriority.LOW,
            }
            self.priority = priority_map[self.quadrant]

    def to_dict(self) -> dict[str, Any]:
        """Serialisiert die Aufgabe als Dictionary."""
        d = asdict(self)
        d["quadrant"] = self.quadrant.name if self.quadrant else None
        d["priority"] = self.priority.name
        d["status"] = self.status.name
        return d

    def mark_started(self) -> None:
        """Markiert die Aufgabe als gestartet."""
        self.status = TaskStatus.RUNNING
        self.started_at = datetime.now(timezone.utc).isoformat()
        self.attempts += 1

    def mark_completed(self, result: str) -> None:
        """Markiert die Aufgabe als erfolgreich abgeschlossen."""
        self.status = TaskStatus.COMPLETED
        self.completed_at = datetime.now(timezone.utc).isoformat()
        self.result = result

    def mark_failed(self, error: str) -> None:
        """Markiert die Aufgabe als fehlgeschlagen."""
        self.status = TaskStatus.FAILED
        self.error = error
        logger.error("Aufgabe %s fehlgeschlagen: %s", self.id, error)


@dataclass
class AgentStats:
    """Statistiken des AgentLoops."""
    total_tasks: int = 0
    completed_tasks: int = 0
    failed_tasks: int = 0
    total_response_time_ms: float = 0.0
    start_time: float = field(default_factory=time.time)

    @property
    def completion_rate(self) -> float:
        """Erfolgsrate als Prozentwert."""
        if self.total_tasks == 0:
            return 0.0
        return (self.completed_tasks / self.total_tasks) * 100.0

    @property
    def average_response_time_ms(self) -> float:
        """Durchschnittliche Antwortzeit in Millisekunden."""
        if self.completed_tasks == 0:
            return 0.0
        return self.total_response_time_ms / self.completed_tasks

    @property
    def uptime_seconds(self) -> float:
        """Laufzeit in Sekunden."""
        return time.time() - self.start_time


# ============================================================
# QUADRANT CLASSIFIER
# ============================================================

class QuadrantClassifier:
    """
    Klassifiziert Aufgaben nach der Eisenhower-Matrix in 4 Quadranten.

    Q1: Wichtig + Dringend    → Sofort erledigen
    Q2: Wichtig + Nicht dringend → Planen und einplanen
    Q3: Dringend + Nicht wichtig → Delegieren
    Q4: Weder noch             → Eliminieren
    """

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config.get("quadrant_engine", {})
        self.thresholds = self.config.get("thresholds", {
            "importance_high": 0.6,
            "urgency_high": 0.6,
        })
        self.scoring = self.config.get("scoring", {})
        self._importance_keywords = self.scoring.get("importance_keywords", {})
        self._urgency_keywords = self.scoring.get("urgency_keywords", {})

    def classify(self, task: Task) -> Quadrant:
        """
        Klassifiziert eine Aufgabe in einen der 4 Quadranten.

        Args:
            task: Die zu klassifizierende Aufgabe

        Returns:
            Der ermittelte Quadrant
        """
        # Scores aus Beschreibung berechnen (falls noch nicht gesetzt)
        if task.importance_score == 0.5 and task.urgency_score == 0.5:
            task.importance_score = self._calculate_importance(task.description)
            task.urgency_score = self._calculate_urgency(task.description)

        importance_high = self.thresholds["importance_high"]
        urgency_high = self.thresholds["urgency_high"]

        is_important = task.importance_score >= importance_high
        is_urgent = task.urgency_score >= urgency_high

        if is_important and is_urgent:
            return Quadrant.Q1_WICHTIG_DRINGEND
        elif is_important and not is_urgent:
            return Quadrant.Q2_WICHTIG_NICHT_DRINGEND
        elif not is_important and is_urgent:
            return Quadrant.Q3_DRINGEND_NICHT_WICHTIG
        else:
            return Quadrant.Q4_WEDER_NOCH

    def prioritize(self, tasks: list[Task]) -> list[Task]:
        """
        Sortiert eine Liste von Aufgaben nach Priorität.

        Args:
            tasks: Liste der zu sortierenden Aufgaben

        Returns:
            Sortierte Liste (höchste Priorität zuerst)
        """
        for task in tasks:
            if task.quadrant is None:
                task.quadrant = self.classify(task)
                task.__post_init__()

        return sorted(
            tasks,
            key=lambda t: (t.priority.value, -t.urgency_score, -t.importance_score)
        )

    def _calculate_importance(self, text: str) -> float:
        """Berechnet den Wichtigkeits-Score anhand von Keywords."""
        text_lower = text.lower()
        score = 0.5  # Basis-Score

        for keyword in self._importance_keywords.get("high", []):
            if keyword in text_lower:
                score = min(1.0, score + 0.2)

        for keyword in self._importance_keywords.get("medium", []):
            if keyword in text_lower:
                score = min(1.0, score + 0.1)

        for keyword in self._importance_keywords.get("low", []):
            if keyword in text_lower:
                score = max(0.0, score - 0.15)

        return round(score, 2)

    def _calculate_urgency(self, text: str) -> float:
        """Berechnet den Dringlichkeits-Score anhand von Keywords."""
        text_lower = text.lower()
        score = 0.5  # Basis-Score

        for keyword in self._urgency_keywords.get("high", []):
            if keyword in text_lower:
                score = min(1.0, score + 0.25)

        for keyword in self._urgency_keywords.get("medium", []):
            if keyword in text_lower:
                score = min(1.0, score + 0.1)

        for keyword in self._urgency_keywords.get("low", []):
            if keyword in text_lower:
                score = max(0.0, score - 0.2)

        return round(score, 2)


# ============================================================
# KIROBI BRAIN (Ollama-Interface)
# ============================================================

class KirobiBrain:
    """
    Schnittstelle zu Ollama — dem lokalen LLM-Server.
    Kein Cloud-Zugriff, alle Berechnungen lokal auf RTX 3090.
    """

    def __init__(self, config: dict[str, Any]) -> None:
        ollama_config = config.get("ollama", {})
        self.host = ollama_config.get("host", "http://localhost:11434")
        self.default_model = ollama_config.get("default_model", "llama3.1:8b")
        self.fallback_model = ollama_config.get("fallback_model", "llama3.1:8b")
        self.timeout = ollama_config.get("timeout_seconds", 300)
        self.model_settings = ollama_config.get("model_settings", {})
        self._client = httpx.AsyncClient(
            base_url=self.host,
            timeout=self.timeout,
        )

    async def think(
        self,
        prompt: str,
        model: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> str:
        """
        Sendet einen Prompt an Ollama und gibt die Antwort zurück.

        Args:
            prompt:        Der Benutzer-Prompt
            model:         Optionales Modell (Standard: default_model)
            system_prompt: Optionaler System-Prompt

        Returns:
            Die generierte Antwort als String
        """
        use_model = model or self.default_model
        settings = self.model_settings.get(use_model, {})

        request_body: dict[str, Any] = {
            "model": use_model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "num_ctx": settings.get("context_length", 4096),
                "num_gpu": settings.get("num_gpu", 99),
                "num_thread": settings.get("num_thread", 8),
                "temperature": settings.get("temperature", 0.7),
                "top_p": settings.get("top_p", 0.9),
            },
        }

        if system_prompt:
            request_body["system"] = system_prompt

        try:
            response = await self._client.post("/api/generate", json=request_body)
            response.raise_for_status()
            data = response.json()
            return data.get("response", "").strip()

        except httpx.TimeoutException:
            logger.warning("Timeout mit Modell %s, versuche Fallback %s", use_model, self.fallback_model)
            if use_model != self.fallback_model:
                return await self.think(prompt, model=self.fallback_model, system_prompt=system_prompt)
            raise

        except httpx.HTTPStatusError as e:
            logger.error("HTTP-Fehler von Ollama: %s", e)
            raise

    async def plan(self, goal: str) -> list[str]:
        """
        Erstellt einen Aufgaben-Plan für ein übergeordnetes Ziel.

        Args:
            goal: Das zu erreichende Ziel

        Returns:
            Liste von Teilaufgaben als Strings
        """
        system_prompt = (
            "Du bist Kirobi, ein autonomer KI-Orchestrator. "
            "Antworte immer auf Deutsch. "
            "Wenn du einen Plan erstellst, gib jede Aufgabe auf einer neuen Zeile aus, "
            "beginnend mit einer Zahl und einem Punkt (z.B. '1. Aufgabe hier'). "
            "Halte Aufgaben konkret, ausführbar und messbar."
        )

        prompt = (
            f"Erstelle einen strukturierten Aktionsplan für folgendes Ziel:\n\n"
            f"ZIEL: {goal}\n\n"
            f"Teile das Ziel in 3-7 konkrete, ausführbare Aufgaben auf. "
            f"Jede Aufgabe soll klar definiert und umsetzbar sein."
        )

        response = await self.think(prompt, system_prompt=system_prompt)

        # Aufgaben aus der Antwort extrahieren
        tasks = []
        for line in response.split("\n"):
            line = line.strip()
            # Nummerierte Listenelemente erkennen
            if line and (
                (len(line) > 2 and line[0].isdigit() and line[1] in ".)")
                or line.startswith("- ")
                or line.startswith("• ")
            ):
                # Nummerierung entfernen
                task_text = line.lstrip("0123456789.-•) ").strip()
                if task_text:
                    tasks.append(task_text)

        if not tasks:
            # Fallback: Gesamte Antwort als einzelne Aufgabe
            tasks = [response]

        return tasks

    async def analyze_task(self, task: Task) -> str:
        """
        Analysiert und bearbeitet eine einzelne Aufgabe.

        Args:
            task: Die zu bearbeitende Aufgabe

        Returns:
            Das Ergebnis der Aufgabe als String
        """
        system_prompt = (
            "Du bist Kirobi, ein autonomer KI-Assistent. "
            "Antworte präzise und hilfreich auf Deutsch. "
            "Wenn du Code erzeugst, nutze Markdown-Codeblöcke. "
            f"Kontext: Aufgabe ist klassifiziert als {task.quadrant.name if task.quadrant else 'UNKLASSIFIZIERT'}, "
            f"Priorität: {task.priority.name}."
        )

        context_info = ""
        if task.context:
            context_info = f"\n\nKontext:\n{json.dumps(task.context, ensure_ascii=False, indent=2)}"

        prompt = f"Bearbeite folgende Aufgabe:\n\n{task.description}{context_info}"

        return await self.think(prompt, system_prompt=system_prompt)

    async def reflect(self, completed_tasks: list[Task], stats: AgentStats) -> str:
        """
        Führt eine Reflexion über abgeschlossene Aufgaben durch.

        Args:
            completed_tasks: Liste der abgeschlossenen Aufgaben
            stats:           Aktuelle Statistiken

        Returns:
            Reflexions-Zusammenfassung
        """
        if not completed_tasks:
            return "Keine Aufgaben zum Reflektieren."

        task_summaries = "\n".join([
            f"- [{t.status.name}] {t.description[:80]}..."
            if len(t.description) > 80 else
            f"- [{t.status.name}] {t.description}"
            for t in completed_tasks[-5:]  # Letzte 5 Aufgaben
        ])

        prompt = (
            f"Reflektiere über die folgenden abgeschlossenen Aufgaben und "
            f"gib eine kurze Zusammenfassung (3-5 Sätze) sowie mögliche Verbesserungen:\n\n"
            f"Statistiken:\n"
            f"  - Abgeschlossen: {stats.completed_tasks}/{stats.total_tasks}\n"
            f"  - Erfolgsrate: {stats.completion_rate:.1f}%\n"
            f"  - Ø Antwortzeit: {stats.average_response_time_ms:.0f}ms\n\n"
            f"Letzte Aufgaben:\n{task_summaries}"
        )

        return await self.think(prompt)

    async def close(self) -> None:
        """Schließt den HTTP-Client."""
        await self._client.aclose()


# ============================================================
# AGENT LOOP
# ============================================================

class AgentLoop:
    """
    Der Haupt-AgentLoop von Kirobi.

    Kontinuierliche Schleife die:
    1. Aufgaben aus der Queue nimmt
    2. Sie klassifiziert und priorisiert (4-Quadranten)
    3. Sie mit dem LLM bearbeitet
    4. Ergebnisse speichert
    5. Regelmäßig reflektiert
    """

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.loop_config = config.get("agent_loop", {})

        # Komponenten initialisieren
        self.brain = KirobiBrain(config)
        self.classifier = QuadrantClassifier(config)

        # Queue und Status
        self._queue: list[Task] = []
        self._completed: list[Task] = []
        self._running = False
        self._stats = AgentStats()

        # Konfigurationswerte
        self.max_queue_size = self.loop_config.get("max_queue_size", 100)
        self.max_concurrent = self.loop_config.get("max_concurrent_tasks", 3)
        self.task_timeout = self.loop_config.get("task_timeout_seconds", 600)
        self.reflection_interval = self.loop_config.get("reflection_interval", 5)
        self.max_retries = self.loop_config.get("max_retries", 3)

        # Workspace
        self.workspace_dir = Path(self.loop_config.get("workspace_dir", "/kirobi/workspace"))
        self.log_dir = Path(self.loop_config.get("log_dir", "/kirobi/logs"))
        self.state_file = Path(self.loop_config.get("state_file", "/kirobi/data/agent_state.json"))

        # Verzeichnisse erstellen
        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.state_file.parent.mkdir(parents=True, exist_ok=True)

        logger.info("AgentLoop initialisiert — Bereit für Aufgaben 🚀")

    async def add_task(self, description: str, **kwargs: Any) -> Task:
        """
        Fügt eine neue Aufgabe zur Queue hinzu.

        Args:
            description: Aufgabenbeschreibung
            **kwargs:    Optionale Task-Felder (context, tags, etc.)

        Returns:
            Die erstellte Aufgabe
        """
        if len(self._queue) >= self.max_queue_size:
            raise RuntimeError(f"Queue voll! Maximale Größe: {self.max_queue_size}")

        task = Task(description=description, **kwargs)

        # Klassifizieren
        task.quadrant = self.classifier.classify(task)
        task.__post_init__()

        logger.info(
            "Aufgabe hinzugefügt [%s]: %s... | Quadrant: %s | Priorität: %s",
            task.id,
            description[:50],
            task.quadrant.name if task.quadrant else "?",
            task.priority.name,
        )

        self._queue.append(task)
        # Queue nach Priorität sortieren
        self._queue = self.classifier.prioritize(self._queue)

        return task

    async def process_task(self, task: Task) -> None:
        """
        Verarbeitet eine einzelne Aufgabe.

        Args:
            task: Die zu verarbeitende Aufgabe
        """
        task.mark_started()
        start_time = time.time()

        logger.info("Verarbeite Aufgabe [%s]: %s...", task.id, task.description[:60])

        try:
            # Aufgabe mit Timeout bearbeiten
            result = await asyncio.wait_for(
                self.brain.analyze_task(task),
                timeout=self.task_timeout,
            )

            task.mark_completed(result)
            elapsed_ms = (time.time() - start_time) * 1000

            self._stats.completed_tasks += 1
            self._stats.total_response_time_ms += elapsed_ms

            logger.info(
                "Aufgabe [%s] abgeschlossen in %.0fms",
                task.id,
                elapsed_ms,
            )

            # Ergebnis in Datei speichern
            await self._save_task_result(task)

        except asyncio.TimeoutError:
            error_msg = f"Timeout nach {self.task_timeout}s"
            task.mark_failed(error_msg)
            self._stats.failed_tasks += 1

        except Exception as e:
            error_msg = str(e)
            task.mark_failed(error_msg)
            self._stats.failed_tasks += 1

            # Retry-Logik
            if task.attempts < task.max_attempts:
                logger.warning(
                    "Aufgabe [%s] fehlgeschlagen (Versuch %d/%d), retry in %ds...",
                    task.id,
                    task.attempts,
                    task.max_attempts,
                    self.loop_config.get("retry_backoff_seconds", 5),
                )
                task.status = TaskStatus.PENDING
                await asyncio.sleep(self.loop_config.get("retry_backoff_seconds", 5))
                self._queue.insert(0, task)  # Wieder vorne in die Queue
                return

        finally:
            self._completed.append(task)
            self._stats.total_tasks += 1

    async def reflect(self) -> None:
        """Führt einen Reflexionsschritt durch."""
        logger.info("Starte Reflexionsschritt...")
        recent = [t for t in self._completed[-self.reflection_interval:]]
        reflection = await self.brain.reflect(recent, self._stats)
        logger.info("Reflexion: %s", reflection[:200] + "..." if len(reflection) > 200 else reflection)

        # Reflexion speichern
        reflection_file = self.log_dir / f"reflection_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        reflection_file.write_text(
            f"Zeitpunkt: {datetime.now().isoformat()}\n"
            f"Statistiken: {self._stats.completion_rate:.1f}% Erfolgsrate\n\n"
            f"{reflection}\n",
            encoding="utf-8",
        )

    async def run(self) -> None:
        """
        Startet den AgentLoop — läuft kontinuierlich bis gestoppt.
        """
        self._running = True
        tick_rate = self.loop_config.get("tick_rate_hz", 1)
        tick_interval = 1.0 / max(tick_rate, 0.1)

        logger.info("AgentLoop gestartet (%.1f ticks/s) 🔄", tick_rate)
        logger.info("Queue-Status: %d Aufgaben", len(self._queue))

        task_count_since_reflection = 0

        while self._running:
            try:
                if self._queue:
                    # Aufgabe aus Queue nehmen (höchste Priorität zuerst)
                    task = self._queue.pop(0)
                    await self.process_task(task)
                    task_count_since_reflection += 1

                    # Reflexion
                    if task_count_since_reflection >= self.reflection_interval:
                        await self.reflect()
                        task_count_since_reflection = 0

                    # Status speichern
                    await self._save_state()

                else:
                    # Keine Aufgaben — warte auf neue
                    if tick_interval > 0:
                        await asyncio.sleep(tick_interval)

            except asyncio.CancelledError:
                logger.info("AgentLoop wurde gestoppt")
                break
            except Exception as e:
                logger.error("Unerwarteter Fehler im AgentLoop: %s", e)
                await asyncio.sleep(5)

        self._running = False
        logger.info(
            "AgentLoop beendet. Statistiken: %d/%d Aufgaben erfolgreich (%.1f%%)",
            self._stats.completed_tasks,
            self._stats.total_tasks,
            self._stats.completion_rate,
        )

    def stop(self) -> None:
        """Stoppt den AgentLoop."""
        self._running = False
        logger.info("AgentLoop Stop angefordert")

    async def _save_task_result(self, task: Task) -> None:
        """Speichert das Ergebnis einer Aufgabe in eine Datei."""
        if not task.result:
            return

        task_dir = self.log_dir / "tasks"
        task_dir.mkdir(exist_ok=True)

        task_file = task_dir / f"task_{task.id}_{datetime.now().strftime('%Y%m%d')}.json"
        task_file.write_text(
            json.dumps(task.to_dict(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    async def _save_state(self) -> None:
        """Speichert den aktuellen Status des AgentLoops."""
        state = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "stats": {
                "total_tasks": self._stats.total_tasks,
                "completed_tasks": self._stats.completed_tasks,
                "failed_tasks": self._stats.failed_tasks,
                "completion_rate": self._stats.completion_rate,
                "average_response_time_ms": self._stats.average_response_time_ms,
                "uptime_seconds": self._stats.uptime_seconds,
            },
            "queue_size": len(self._queue),
            "completed_count": len(self._completed),
        }
        self.state_file.write_text(
            json.dumps(state, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


# ============================================================
# SELF IMPROVEMENT LOOP
# ============================================================

class SelfImprovementLoop:
    """
    Analysiert die Performance des AgentLoops und schlägt Optimierungen vor.
    Kirobi verbessert sich dadurch selbst über die Zeit.
    """

    def __init__(self, agent_loop: AgentLoop, config: dict[str, Any]) -> None:
        self.agent = agent_loop
        self.si_config = config.get("self_improvement", {})
        self.enabled = self.si_config.get("enabled", True)
        self.analysis_interval = self.si_config.get("analysis_interval", 20)
        self.history_file = Path(
            self.si_config.get("history_file", "/kirobi/data/optimization_history.json")
        )
        self.history_file.parent.mkdir(parents=True, exist_ok=True)

    async def analyze_and_optimize(self) -> dict[str, Any]:
        """
        Analysiert aktuelle Performance-Metriken und schlägt Optimierungen vor.

        Returns:
            Dictionary mit Analyseergebnissen und Optimierungsvorschlägen
        """
        if not self.enabled:
            return {}

        stats = self.agent._stats

        analysis: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "metrics": {
                "completion_rate": stats.completion_rate,
                "average_response_time_ms": stats.average_response_time_ms,
                "error_rate": (stats.failed_tasks / max(stats.total_tasks, 1)) * 100,
                "uptime_hours": stats.uptime_seconds / 3600,
            },
            "optimizations": [],
        }

        # Performance-Analyse
        if stats.completion_rate < 80:
            analysis["optimizations"].append({
                "type": "error_handling",
                "suggestion": "Fehlerrate zu hoch — Retry-Strategie anpassen",
                "action": "increase_retry_backoff",
            })

        if stats.average_response_time_ms > 30000:  # > 30 Sekunden
            analysis["optimizations"].append({
                "type": "model_selection",
                "suggestion": "Antwortzeiten zu hoch — kleineres Modell für einfache Aufgaben",
                "action": "use_smaller_model_for_simple_tasks",
            })

        if len(self.agent._queue) > 50:
            analysis["optimizations"].append({
                "type": "queue_management",
                "suggestion": "Queue zu groß — Niedrig-Priorität-Aufgaben pausieren",
                "action": "pause_low_priority_tasks",
            })

        # Optimierungen anwenden
        for opt in analysis["optimizations"]:
            logger.info("Self-Improvement: %s", opt["suggestion"])

        # Analyse speichern
        await self._save_analysis(analysis)

        return analysis

    async def _save_analysis(self, analysis: dict[str, Any]) -> None:
        """Speichert die Analyse in die Histor-Datei."""
        history: list[dict[str, Any]] = []

        if self.history_file.exists():
            try:
                history = json.loads(self.history_file.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                history = []

        history.append(analysis)
        # Maximal 100 Einträge behalten
        history = history[-100:]

        self.history_file.write_text(
            json.dumps(history, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


# ============================================================
# HERMES AGENT (Kommunikation)
# ============================================================

class HermesAgent:
    """
    Kommunikationsagent für Benachrichtigungen und Berichte.
    Zuständig für: Desktop-Notifications, Webhooks, E-Mail-Alerts.
    """

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config.get("hermes", {})
        self.enabled = self.config.get("enabled", True)
        self.channels = self.config.get("channels", {})

    async def notify(self, title: str, message: str, level: str = "info") -> None:
        """
        Sendet eine Benachrichtigung über alle konfigurierten Kanäle.

        Args:
            title:   Benachrichtigungstitel
            message: Nachrichtentext
            level:   Priorität (info, warning, error)
        """
        if not self.enabled:
            return

        logger.info("Hermes: [%s] %s — %s", level.upper(), title, message[:100])

        # Desktop-Benachrichtigung
        if self.channels.get("desktop", {}).get("enabled", True):
            await self._send_desktop_notification(title, message, level)

        # Webhook
        if self.channels.get("webhook", {}).get("enabled", False):
            await self._send_webhook(title, message, level)

    async def _send_desktop_notification(
        self, title: str, message: str, level: str
    ) -> None:
        """Sendet eine Desktop-Benachrichtigung via notify-send."""
        urgency_map = {"info": "normal", "warning": "normal", "error": "critical"}
        urgency = urgency_map.get(level, "normal")

        try:
            proc = await asyncio.create_subprocess_exec(
                "notify-send",
                "--urgency", urgency,
                "--app-name", "Kirobi",
                title,
                message,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
        except FileNotFoundError:
            pass  # notify-send nicht verfügbar — ignorieren

    async def _send_webhook(
        self, title: str, message: str, level: str
    ) -> None:
        """Sendet eine Webhook-Benachrichtigung."""
        webhook_config = self.channels.get("webhook", {})
        url = webhook_config.get("url", "")
        if not url:
            return

        payload = {
            "title": title,
            "message": message,
            "level": level,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "source": "kirobi",
        }

        try:
            async with httpx.AsyncClient(timeout=10) as client:
                await client.post(url, json=payload)
        except Exception as e:
            logger.debug("Webhook-Fehler: %s", e)


# ============================================================
# KONFIGURATION LADEN
# ============================================================

def load_config(config_path: Optional[str] = None) -> dict[str, Any]:
    """
    Lädt die Kirobi-Konfiguration aus einer YAML-Datei.

    Args:
        config_path: Optionaler Pfad zur Konfigurationsdatei

    Returns:
        Konfiguration als Dictionary
    """
    if config_path is None:
        # Standard-Suchpfade
        search_paths = [
            os.environ.get("KIROBI_CONFIG", ""),
            "/kirobi/kirobi-core/config.yaml",
            Path(__file__).parent.parent / "config.yaml",
            "config.yaml",
        ]
        for path in search_paths:
            if path and Path(path).exists():
                config_path = str(path)
                break

    if config_path and Path(config_path).exists():
        logger.info("Lade Konfiguration: %s", config_path)
        with open(config_path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}

    logger.warning("Keine Konfigurationsdatei gefunden — verwende Standardwerte")
    return {}


# ============================================================
# HAUPTPROGRAMM
# ============================================================

async def main() -> None:
    """Startet das Kirobi-System."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Kirobi Autonomous AI Orchestrator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--config", "-c",
        help="Pfad zur Konfigurationsdatei (config.yaml)",
        default=None,
    )
    parser.add_argument(
        "--task", "-t",
        help="Einzelne Aufgabe ausführen und beenden",
        default=None,
    )
    parser.add_argument(
        "--interactive", "-i",
        action="store_true",
        help="Interaktiver Modus",
    )

    args = parser.parse_args()

    # Konfiguration laden
    config = load_config(args.config)

    # Agenten initialisieren
    agent = AgentLoop(config)
    hermes = HermesAgent(config)
    improver = SelfImprovementLoop(agent, config)

    await hermes.notify("Kirobi", "System gestartet 🚀", level="info")

    try:
        if args.task:
            # Einzelne Aufgabe ausführen
            logger.info("Führe einzelne Aufgabe aus: %s", args.task)
            task = await agent.add_task(args.task)
            await agent.process_task(task)
            print(f"\n{'='*60}")
            print(f"Aufgabe: {task.description}")
            print(f"Status:  {task.status.name}")
            print(f"{'='*60}")
            print(task.result or task.error or "Kein Ergebnis")
            print(f"{'='*60}\n")

        elif args.interactive:
            # Interaktiver Modus
            print("\n🤖 Kirobi Interaktiver Modus (Strg+C zum Beenden)\n")
            print("Tippe eine Aufgabe und drücke Enter:\n")

            while True:
                try:
                    user_input = input("Du: ").strip()
                    if not user_input:
                        continue
                    if user_input.lower() in ("exit", "quit", "bye", "tschüss"):
                        break

                    task = await agent.add_task(user_input)
                    await agent.process_task(task)
                    print(f"\nKirobi [{task.quadrant.name if task.quadrant else '?'}]:")
                    print(task.result or task.error or "Kein Ergebnis")
                    print()

                except KeyboardInterrupt:
                    break

        else:
            # Dauerhafter AgentLoop
            # Beispiel-Aufgaben hinzufügen (beim ersten Start)
            if not agent.state_file.exists():
                logger.info("Erster Start — füge Initialisierungsaufgaben hinzu")
                await agent.add_task(
                    "Überprüfe alle Systemdienste und erstelle einen Statusbericht",
                    tags=["system", "monitoring"],
                )
                await agent.add_task(
                    "Analysiere verfügbare Ollama-Modelle und empfehle eine optimale Konfiguration für RTX 3090",
                    tags=["kirobi", "optimization"],
                )

            # AgentLoop starten
            loop_task = asyncio.create_task(agent.run())

            # Self-Improvement periodisch ausführen
            async def improvement_worker() -> None:
                while agent._running:
                    await asyncio.sleep(
                        improver.analysis_interval * 60  # In Minuten
                    )
                    await improver.analyze_and_optimize()

            improvement_task = asyncio.create_task(improvement_worker())

            try:
                await asyncio.gather(loop_task, improvement_task)
            except KeyboardInterrupt:
                agent.stop()

    except KeyboardInterrupt:
        logger.info("Kirobi wird beendet...")
        agent.stop()

    finally:
        await agent.brain.close()
        await hermes.notify("Kirobi", "System gestoppt", level="info")
        logger.info("Auf Wiedersehen! 👋")


if __name__ == "__main__":
    asyncio.run(main())
