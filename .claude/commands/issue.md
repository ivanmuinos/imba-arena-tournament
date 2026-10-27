---
description: Implementa un issue de GitHub de punta a punta (worktree, código, tests, PR)
argument-hint: <número de issue>
---

Implementá el issue #$ARGUMENTS de este repo de punta a punta. Seguí `CONTRIBUTING.md`.

## 1. Leer el issue
- `gh issue view $ARGUMENTS --json number,title,body,labels,state,assignees`
- Si está cerrado o no existe, pará y avisá.
- Asignátelo: `gh issue edit $ARGUMENTS --add-assignee @me`.
- Si el issue es ambiguo o le faltan criterios de aceptación, preguntame antes de escribir código.

## 2. Branch y worktree
- Prefijo según label: `bug` → `fix/`, `balance` → `balance/`, `chore` → `chore/`, cualquier otro → `feat/`.
- Nombre: `<prefijo><número>-<slug>`; el slug sale del título, en kebab-case, sin tildes, 2-5 palabras (ej. `feat/42-chat-ingame`).
- `git fetch origin` y creá el worktree desde `origin/main` (nunca trabajes en `main`):
  `git worktree add .claude/worktrees/$ARGUMENTS -b <branch> origin/main`
  y hacé todo el trabajo dentro de `.claude/worktrees/$ARGUMENTS` (cd ahí; rutas absolutas a ese directorio al editar).
- En el worktree nuevo: `godot --headless --path . --import >/dev/null 2>&1 || true` (arma la caché de `class_name`).

## 3. Implementar
- Leé el código relacionado antes de tocarlo y seguí su estilo.
- Mantenete dentro del alcance del issue. Lo que encuentres fuera de alcance, anotalo para proponerlo como issue aparte.
- Lógica nueva o cambiada → tests nuevos o actualizados en `tests/`.
- Evitá tocar `project.godot`, autoloads o `.tscn` grandes salvo que el issue lo necesite; si los tocás, mencionalo en el PR.
- Nada de builds ni zips.

## 4. Tests
- `./run_tests.sh` hasta que pase. Si el cambio toca menú, partida o red, corré también `tests/smoke.sh`.

## 5. Commit, rebase y PR
- Commits chicos con mensajes claros que mencionen `#$ARGUMENTS`.
- `git fetch origin && git rebase origin/main`; si entró algo nuevo, volvé a correr los tests.
- `git push -u origin <branch>` (después de un rebase sobre una branch ya pusheada: `--force-with-lease`, sólo en tu branch).
- `gh pr create --title "<título del issue>"` con un cuerpo que siga `.github/pull_request_template.md`: `Closes #$ARGUMENTS`, qué cambia, cómo probarlo y el checklist marcado.

## 6. Cierre
- Devolveme el link del PR, un resumen corto y lo que quedó fuera de alcance.
- Recordame mirar el CI con `gh pr checks --watch` y que el worktree se borra después del merge con
  `git worktree remove .claude/worktrees/$ARGUMENTS`.
