# Cómo trabajamos

Todo gratis: GitHub Issues + Projects + Actions + Claude Code local.

## Flujo

```
idea → issue → branch/worktree → prompt a Claude → PR (Closes #N) → CI verde → squash merge
```

1. **Idea → issue.** `gh issue create` o desde la web con el template *Feature / idea*. Escribilo
   como si fuera el prompt: qué queremos, criterios de aceptación, archivos que toca.
2. **Asignátelo** y movelo a *En curso* en el tablero. Un issue = una persona.
3. **Branch** con el número del issue:
   - `feat/42-chat-ingame`, `fix/57-druid-crash`, `chore/...`, `balance/...`
4. **Worktree** para trabajar varias features en paralelo sin mezclarlas:
   ```sh
   claude -w feat/42-chat-ingame          # Claude Code crea el worktree y la branch
   # o a mano:
   git worktree add ../iat-42 -b feat/42-chat-ingame
   ```
5. **Prompt:** `Implementá el issue #42 (gh issue view 42). Seguí CONTRIBUTING.md.`
6. **PR:** `gh pr create --fill` con `Closes #42` en la descripción. El issue se cierra solo al mergear.
7. **Merge:** CI en verde + review del otro dev → *Squash and merge* → borrar branch.

## Reglas para que todo sea mergeable

- **PRs chicos.** Una feature o fix por PR. Si crece mucho, partilo en varios issues.
- **Rebase seguido:** `git fetch && git rebase origin/main` antes de abrir el PR y si `main` avanzó.
- **Nadie pushea a `main`.** Todo entra por PR con CI en verde.
- **Archivos compartidos = cuidado.** `project.godot`, autoloads y `.tscn` grandes generan conflictos
  difíciles. Si tu issue los toca, anotalo en *Archivos / zonas que toca* y avisá.
- **Cada feature en sus propios scripts/escenas/datos** en lugar de agrandar un archivo central.
- **Lo que no está terminado se mergea deshabilitado** (como los héroes deshabilitados), no se deja
  una branch abierta semanas.
- **Nada de builds en el repo.** Los zips van a GitHub Releases.

## Tests

```sh
./run_tests.sh      # suite headless, la misma que corre CI
tests/smoke.sh      # smoke del juego real (menú, partida, servidor dedicado)
```
