# Cómo trabajar en el proyecto

Todo gratis: GitHub Issues + Actions (repo público) + Claude Code local con la suscripción de cada uno.

```
idea → issue → /issue N en Claude Code → PR (Closes #N) → CI verde → squash merge
```

## 1. Primera vez

1. Pedí acceso de colaborador al repo y cloná:
   ```sh
   git clone git@github.com:ivanmuinos/imba-arena-tournament.git
   ```
2. Instalá:
   - **Godot 4.7.2** con `godot` en el PATH (en Windows, ver "Cómo jugar" en el README).
   - **GitHub CLI** (`brew install gh`) y logueate: `gh auth login`.
   - **Claude Code**, logueado con **tu propia** suscripción (`claude` → `/login`).
3. Importá el proyecto y corré los tests:
   ```sh
   godot --headless --path . --import
   ./run_tests.sh
   ```

## 2. Ideas → issues

Los issues están en https://github.com/ivanmuinos/imba-arena-tournament/issues (o `gh issue list`).

- Crealo con el template **Feature / idea** o **Bug** (web o `gh issue create`).
- Escribilo como si fuera el prompt: qué queremos, criterios de aceptación, archivos que toca, qué queda fuera.
- Si todavía no está claro, ponele la label `idea`; cuando esté listo para hacer, sacásela.
- Labels: `feature`, `bug`, `balance`, `ui`, `heroe`, `arena`, `net`, `chore`, `idea`.
- **Un issue = una persona.** Asignátelo antes de empezar para no pisarse.

## 3. Implementar un issue con Claude Code

Desde la carpeta del repo, en `main` actualizado:

```sh
git switch main && git pull
claude
> /issue 42
```

El comando (`.claude/commands/issue.md`) hace:

1. Lee el issue y te lo asigna.
2. Crea la branch `feat/42-...` (o `fix/`, `balance/`, `chore/`) en un worktree aparte en `.claude/worktrees/42`.
3. Implementa, con tests en `tests/`.
4. Corre `./run_tests.sh` hasta que pase.
5. Rebasea sobre `main`, pushea y abre el PR con `Closes #42`.

Si el issue es ambiguo te pregunta antes de escribir código. Podés corregirlo en cualquier momento.
Varias features en paralelo = una sesión de `claude` por issue: cada una tiene su worktree y no se mezclan.

Sin Claude, el flujo es el mismo a mano:

```sh
git fetch origin
git worktree add .claude/worktrees/42 -b feat/42-chat-ingame origin/main
cd .claude/worktrees/42
# ... código + tests ...
./run_tests.sh
git push -u origin feat/42-chat-ingame
gh pr create --fill        # agregá "Closes #42" en la descripción
```

## 4. PR → merge

1. El CI corre `./run_tests.sh` en GitHub: `gh pr checks --watch`.
2. El otro dev lo revisa (o lo prueba bajando la branch).
3. Si `main` avanzó, GitHub pide actualizar la branch: botón **Update branch**, o `git rebase origin/main` y `git push --force-with-lease`.
4. **Squash and merge.** La branch remota se borra sola y el issue se cierra solo.
5. Borrá el worktree local: `git worktree remove .claude/worktrees/42`.

`main` está protegida: no se puede pushear directo, todo entra por PR con el check `tests` en verde.

## 5. Reglas para que todo sea mergeable

- **PRs chicos.** Una feature o fix por PR. Si crece mucho, partilo en varios issues.
- **Rebase seguido** sobre `main`, y mergeá rápido: una branch que vive semanas siempre choca.
- **Archivos compartidos = cuidado.** `project.godot`, autoloads y `.tscn` grandes generan conflictos
  difíciles. Si tu issue los toca, anotalo en *Archivos / zonas que toca* y avisá.
- **Cada feature en sus propios scripts/escenas/datos** en lugar de agrandar un archivo central.
- **Lo que no está terminado se mergea deshabilitado** (como los héroes deshabilitados).
- **Nada de builds en el repo.** Los zips van a GitHub Releases.

## Tests

```sh
./run_tests.sh              # suite headless, la misma que corre CI
./run_tests.sh net steam    # sólo esas suites
tests/smoke.sh              # smoke del juego real (menú, partida, servidor dedicado)
```
