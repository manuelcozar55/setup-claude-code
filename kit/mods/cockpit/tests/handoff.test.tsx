import { expect, mock, test, type TestBody } from 'claude-code/testing'

import { HANDOFF_PROMPT, fillFor, nextLine, redact } from '../hooks/register'

const RUN = { args: '', origin: { kind: 'composer' as const }, presentation: { isFullscreen: true, columns: 160 } }
// Fake secrets assembled at runtime so secret scanners don't flag the test itself.
const FAKE_SK = ['sk', 'ant', 'abcdefghijklmnopqrstuvwxyz'].join('-')
const FAKE_GH = 'gh' + 'p_' + 'abcdefghijklmnopqrstuvwxyz0123'
const FAKE_AWS = 'AK' + 'IA' + 'ABCDEFGHIJKLMNOP'
const EST = '/work/proyecto/.claude/estado'
const HOME = '/usr/u'
const BIN = `${HOME}/.claude/bin/handoff`
const TMP = '/tmp/cockpit-handoff.Ab12Cd'
const HASH = 'a'.repeat(64)
const NEW = `## Objetivo\nhaz X\n## Invariantes\n- no tocar Y\n## Plan\n- [ ] T1\n## Siguiente acción\nT1\nclave: ${FAKE_SK}\n`
const PREV = '# Estado\n\n## Objetivo\nhaz X  \ntal cual\n\n## Invariantes\n- no tocar Y\n## Plan\n- [ ] T1\n## Skills sugeridas\n- grilling\n'

type Run = { argv: readonly string[] }
const ok = (stdout = '') => ({ value: { exitCode: 0, stdout, stderr: '' } }) as never
const no = () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }) as never

// A fake repo and a stub of the handoff CLI that follows the contract (exit 0/2/3/4); the files live in a map.
// `cli` is one exit code per call (the last one repeats). On 0 the stub «merges» by writing the draft as nucleo.md.
function repo(
  on: Parameters<TestBody>[1],
  files: Record<string, string>,
  opts: { links?: string[]; isRepo?: boolean; top?: string; cwd?: string; home?: string; env?: string; cli?: number[]; stderr?: string; noBin?: boolean; statePath?: string; claudeHome?: string; stateFails?: boolean; session?: () => string; live?: number; beforeState?: (count: number) => Promise<void>; migrateCode?: number; tope?: number; estadoMd?: string } = {},
) {
  let stateReads = 0
  const runs: Run[] = []
  const writes: { path: string; text: string }[] = []
  const calls: { argv: readonly string[]; draft: string }[] = []
  const home = opts.home ?? HOME
  const bin = `${opts.claudeHome ?? `${home}/.claude`}/bin/handoff`
  if (!opts.noBin) files[bin] = '#!/usr/bin/env bash\n'
  on('session.cwd', () => ({ value: opts.cwd ?? '/work/proyecto/sub' }))
  on('session.id', () => ({ value: opts.session?.() ?? 'sesion-1' }) as never)
  on('process.run', async (_, e) => {
    runs.push(e)
    const a = e.argv.join(' ')
    if (a === 'printenv HOME') return ok(home)
    if (a === 'printenv CLAUDE_HOME') return ok(opts.claudeHome ?? '')
    if (a === 'printenv COCKPIT_AUTO_HANDOFF') return opts.env ? ok(opts.env) : no()
    if (a.includes('--show-toplevel')) return opts.isRepo === false ? no() : ok(`${opts.top ?? '/work/proyecto'}\n`)
    if (e.argv[0] === 'find') return ok((opts.links ?? []).join('\n'))
    if (e.argv[0] === 'mktemp') return ok(`${TMP}\n`)
    if (e.argv[0] === 'rm') {
      for (const p of e.argv.slice(2)) delete files[p]
      return ok()
    }
    if (e.argv[0] === bin && e.argv[1] === '--estado' && opts.stateFails) return no()
    if (e.argv[0] === bin && e.argv[1] === '--estado') {
      await opts.beforeState?.(++stateReads)
      if (!e.argv.includes('--raiz') && !opts.statePath) return { value: { exitCode: 3, stdout: '', stderr: '' } } as never
      return ok(JSON.stringify({ nucleo: opts.statePath ?? `${opts.top ?? '/work/proyecto'}/.claude/estado/nucleo.md`, pct: 1, bytes: 10, tope: opts.tope ?? 5700, dueno: null, agentes_vivos: opts.live ?? 0, ...(opts.estadoMd ? { modo: 'estado-md', estado: opts.estadoMd } : {}) }))
    }
    if (e.argv[0] === bin && e.argv[1] === '--migrar') {
      const path = opts.statePath ?? `${EST}/nucleo.md`
      const archivo = path.replace('/nucleo.md', '/archivo/nucleo-20261020T000000Z.md')
      if (opts.migrateCode) return { value: { exitCode: opts.migrateCode, stdout: '', stderr: 'estado cambió o dueño ajeno' } } as never
      files[archivo] = files[path] ?? ''
      delete files[path]
      return ok(JSON.stringify({ nucleo: path, sha256: HASH, archivo }))
    }
    if (e.argv[0] === bin) {
      const draft = files[TMP] ?? ''
      calls.push({ argv: e.argv, draft })
      const seq = opts.cli ?? [0]
      const code = seq[Math.min(calls.length - 1, seq.length - 1)] ?? 0
      if (code === 0) files[opts.estadoMd ?? opts.statePath ?? `${e.argv[e.argv.indexOf('--raiz') + 1]}/.claude/estado/nucleo.md`] = draft
      return { value: { exitCode: code, stdout: JSON.stringify({ nucleo: opts.estadoMd ?? opts.statePath ?? `${EST}/nucleo.md`, sha256: HASH }), stderr: opts.stderr ?? '' } } as never
    }
    return ok()
  })
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }) as never)
  on('fs.list', () => ({ value: Object.keys(files).filter(p => p.startsWith(EST + '/')).map(p => ({ name: p.slice(EST.length + 1), kind: 'file' })) }) as never)
  on('fs.write', (_, e) => {
    writes.push(e)
    files[e.path] = e.text
    return { value: undefined }
  })
  return { runs, writes, files, calls }
}
const fork = (on: Parameters<TestBody>[1], text: string, seen: { prompt: string; n: number } = { prompt: '', n: 0 }) => {
  on('model.fork', (_, e) => {
    seen.prompt = e.prompt
    seen.n++
    return { value: { isAnswered: true, text, usage: {} } } as never
  })
  return seen
}

for (const compact of [true, false]) {
  test(`presupuesto UTF-8: segundo borrador ${compact ? 'compacto guarda' : 'grande conserva contexto sin guardar'}`, async ($, on) => {
    const timer = mock.clock(on)
    const prompts: string[] = []
    const seen = auto(on, { tokens: 1, forkText: prompt => {
      prompts.push(prompt)
      return compact && prompts.length === 2 ? PLAN : '## Plan\n' + 'á'.repeat(2500)
    } })
    const previous = '# Estado\n## Encargo original (literal)\n' + 'a'.repeat(900) + '\n## Invariantes vigentes\n' + 'b'.repeat(1000) + '\n'
    const r = repo(on, { [`${EST}/nucleo.md`]: previous })
    const result = await $.command.run({ ...RUN, command: 'handoff' })
    await timer.advance(400)
    expect(prompts).toHaveLength(2)
    expect(prompts[0]).toContain('bytes UTF-8')
    expect(prompts[1]).toContain('último intento')
    expect(r.calls).toHaveLength(compact ? 1 : 0)
    expect(seen.cleared).toBe(compact ? 1 : 0)
    if (!compact) {
      expect(result.text).toContain('no guardo ni limpio')
      expect(r.files[`${EST}/nucleo.md`]).toBe(previous)
      expect(r.writes).toEqual([])
    }
  })
}

test('presupuesto: sale del tope que da handoff --estado, no de un 6500 fijo', async ($, on) => {
  const seen = fork(on, NEW)
  repo(on, {}, { tope: 4700 })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(seen.prompt).toContain(`como máximo ${4700 - 768} bytes UTF-8`)
})

test('sin nucleo: el fork redacta el borrador, se redacta y se delega en el CLI con ruta absoluta, raíz y sesión', async ($, on) => {
  const seen = fork(on, 'Aquí tienes:\n' + NEW)
  const r = repo(on, {})
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo revisar el dock' })

  expect(seen.prompt).toContain('Aún no hay nucleo.md')
  expect(seen.prompt).toContain('## Ficheros tocados')
  expect(seen.prompt).toContain('## Objetivo')
  expect(seen.prompt).toContain('## Invariantes')
  expect(seen.prompt).toContain('La próxima sesión se centrará en: revisar el dock')
  expect(r.calls).toHaveLength(1)
  expect(r.calls[0]?.argv).toEqual([BIN, '--desde', TMP, '--raiz', '/work/proyecto', '--sesion', 'sesion-1', '--json'])
  const draft = r.calls[0]?.draft ?? ''
  expect(draft.startsWith('## Objetivo\nhaz X\n')).toBe(true)
  expect(draft).not.toContain('Aquí tienes')
  expect(draft).not.toContain(FAKE_SK)
  expect(draft).toContain('[REDACTADO]')
  expect(r.writes.map(w => w.path)).toEqual([TMP])
  expect(res.text).toContain(`Guardado en ${EST}/nucleo.md`)
})

test('con nucleo: el prompt lleva el estado como datos y el mod no escribe nucleo.md ni sus copias', async ($, on) => {
  const seen = fork(on, '## Plan\n- [x] T1 (make test, exit 0)\n## Ficheros tocados\n- /a\n')
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })

  expect(seen.prompt).toContain('haz X')
  expect(seen.prompt).toContain('no los devuelvas')
  expect(seen.prompt).not.toContain('Aún no hay nucleo.md')
  expect(r.writes.map(w => w.path)).toEqual([TMP])
  expect(r.runs.some(x => ['mv', 'cp'].includes(x.argv[0] ?? '') || x.argv.includes('--git-path') || x.argv.includes('check-ignore'))).toBe(false)
})

test('con ESTADO.md: el prompt lleva ESTADO.md como estado actual y no el aviso de «aún no hay nucleo.md»', async ($, on) => {
  const seen = fork(on, '## Plan\n- [x] T1\n## Pendientes\n- p\n')
  const estadoMd = '/work/proyecto/ESTADO.md'
  repo(on, { [estadoMd]: '# Estado\n\n- Objetivo (una línea): haz X\n\n## Pendientes y riesgos\n- (persona) abrir PR\n' }, { estadoMd })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })

  expect(seen.prompt).toContain('<nucleo-actual>')
  expect(seen.prompt).toContain('(persona) abrir PR')
  expect(seen.prompt).not.toContain('Aún no hay nucleo.md')
})

test('con ESTADO.md: el recibo apunta a ESTADO.md y el /clear rellena con la viñeta «Siguiente acción»', async ($, on) => {
  const clock = mock.clock(on)
  const estadoMd = '/work/proyecto/ESTADO.md'
  const seen = auto(on, { tokens: 130_000, forkText: '## Plan\n- [ ] T2\n- Siguiente acción: T2 con `make test`\n  detalle\n' })
  repo(on, { [estadoMd]: '# Estado\n' }, { estadoMd })
  await $.turn.complete(DONE_TURN)
  await clock.advance(400)
  await clock.advance(400)
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual([`adelante con la Siguiente acción de ${estadoMd}: T2 con \`make test\` (sigue en ${estadoMd})`])
})

test('el prompt pide los tres campos de la decisión 13: correcciones, ficheros calientes con rango y rc', async ($, on) => {
  const seen = fork(on, NEW)
  repo(on, {})
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(seen.prompt).toMatch(/correcciones literales/i)
  expect(seen.prompt).toContain('ruta:L120-180')
  expect(seen.prompt).toContain('→ rc=N')
})

test('borrador temporal: se crea con mktemp, se fija a 600 antes de usarlo y se borra al terminar', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {})
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  const order = r.runs.map(x => x.argv[0])
  expect(r.runs.find(x => x.argv[0] === 'mktemp')).toBeTruthy()
  expect(r.runs.find(x => x.argv[0] === 'chmod')?.argv).toEqual(['chmod', '600', '--', TMP])
  expect(order.indexOf('chmod')).toBeLessThan(r.runs.findIndex(x => x.argv[0] === BIN && x.argv.includes('--desde')))
  expect(r.runs.find(x => x.argv[0] === 'rm')?.argv).toEqual(['rm', '-f', '--', TMP])
  expect(order.indexOf('rm')).toBeGreaterThan(r.runs.findIndex(x => x.argv[0] === BIN && x.argv.includes('--desde')))
  expect(TMP in r.files).toBe(false)
})

test('borrador temporal: se borra también si el CLI rechaza el borrador', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {}, { cli: [2], stderr: 'cabecera desconocida: ## Cosas' })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.runs.some(x => x.argv[0] === 'rm' && x.argv.includes(TMP))).toBe(true)
})

test('una respuesta sin secciones no escribe nada ni llama al CLI', async ($, on) => {
  fork(on, 'No puedo.')
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.writes).toEqual([])
  expect(r.calls).toEqual([])
  expect(res.text).toContain('Handoff fallido')
})

for (const [name, o] of [
  ['fuera de un repo git', { isRepo: false }],
  ['con la raíz en $HOME', { top: HOME }],
  ['con la raíz en $HOME/.claude', { top: `${HOME}/.claude` }],
  ['bajo $HOME/.claude/**', { top: `${HOME}/.claude/worktrees/x` }],
] as const) {
  test(`sin proyecto (${name}): no hay fork, ni borrador, ni CLI`, async ($, on) => {
    const seen = fork(on, NEW)
    const r = repo(on, {}, o)
    const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
    expect(seen.n).toBe(0)
    expect(r.writes).toEqual([])
    expect(r.calls).toEqual([])
    expect(res.text).toContain('Handoff fallido')
    expect(res.text).toContain('proyecto')
  })
}

test('sin el binario handoff: aviso con la orden de instalación y sin fusión de reserva', async ($, on) => {
  const seen = fork(on, NEW)
  const r = repo(on, {}, { noBin: true })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(res.text).toContain(BIN)
  expect(res.text).toContain('install.sh')
  expect(seen.n).toBe(0)
  expect(r.writes).toEqual([])
})

test('exit 2: informa que el borrador es inválido con lo que dijo el CLI', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {}, { cli: [2], stderr: 'cabecera desconocida: ## Cosas\n' })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(res.text).toContain('borrador inválido')
  expect(res.text).toContain('cabecera desconocida: ## Cosas')
  expect(r.calls).toHaveLength(1)
  expect(r.files[`${EST}/nucleo.md`]).toBeUndefined()
})

test('exit 3: dice que no hay proyecto', async ($, on) => {
  fork(on, NEW)
  repo(on, {}, { cli: [3] })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(res.text).toContain('proyecto')
  expect(res.text).not.toContain('Guardado')
})

test('exit 4: reintenta una vez con el mismo borrador y, si pasa, guarda', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {}, { cli: [4, 0] })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.calls).toHaveLength(2)
  expect(r.calls[1]?.draft).toBe(r.calls[0]?.draft)
  expect(res.text).toContain('Guardado en')
})

test('exit 4 dos veces: no reintenta más y avisa de que nucleo.md cambió', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {}, { cli: [4] })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.calls).toHaveLength(2)
  expect(res.text).toContain('cambió durante la fusión')
  expect(res.text).not.toContain('Guardado')
})

test('raíz: git desde el cwd de la sesión', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {}, { cwd: '/work/proyecto/sub/dir' })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.runs.find(x => x.argv.includes('--show-toplevel'))?.argv.slice(0, 3)).toEqual(['git', '-C', '/work/proyecto/sub/dir'])
})

test('redact tapa claves conocidas y asignaciones, y deja el resto', () => {
  expect(redact(`token: ${FAKE_GH}`)).toBe('token: [REDACTADO]')
  expect(redact(`password=hunter2 y ${FAKE_AWS}`)).toBe('password=[REDACTADO] y [REDACTADO]')
  expect(redact('ver /tmp/handoff.md y el commit abc123')).toBe('ver /tmp/handoff.md y el commit abc123')
})

test('redact cubre Bearer, claves privadas, URLs con credenciales, pat de GitHub/GitLab y JSON', () => {
  const pem = '-----BEGIN ' + 'RSA PRIVATE KEY-----\nabc\ndef\n-----END ' + 'RSA PRIVATE KEY-----'
  expect(redact('Authorization: Bearer ' + 'abc.def-123')).toBe('Authorization: Bearer [REDACTADO]')
  expect(redact(`antes\n${pem}\ndespues`)).toBe('antes\n[REDACTADO]\ndespues')
  expect(redact('git clone https://' + 'user:pa55@host/repo.git')).toBe('git clone https://[REDACTADO]@host/repo.git')
  expect(redact('github_' + 'pat_' + 'abcdefghijklmnopqrstuvwxyz')).toBe('[REDACTADO]')
  expect(redact('gl' + 'pat-' + 'abcdefghijklmnopqrstuvwxyz')).toBe('[REDACTADO]')
  expect(redact('{"password": "hunter 2", "ok": 1}')).toBe('{"password": [REDACTADO], "ok": 1}')
  expect(redact("secret='dos palabras' fin")).toBe("secret=[REDACTADO] fin")
})

// ── Automatic handoff, compaction veto and /nueva
const DONE_TURN = { answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' as const }
const FILL = 'adelante con la Siguiente acción de .claude/estado/nucleo.md: T2'
const PLAN = '## Plan\n- [ ] T2\n## Siguiente acción\nT2\n'

// The context read is throttled by the clock (it starts at 0), so tests that read it twice start it at 10 s.
// The engine beneath the mod: usage (limit 180k = 200k - 20k buffer), agents, fork, clear and fill.
function auto(
  on: Parameters<TestBody>[1],
  o: { tokens: number; window?: number; agents?: { id: string; status: string }[]; usageFailsAfter?: number; forkText?: string | ((prompt: string) => string); fill?: { isFilled: boolean; refusal?: 'dialog' } | 'throws'; clearFails?: boolean; draft?: string | (() => string); beforeFork?: () => Promise<void>; afterClear?: () => Promise<void> },
) {
  const seen = { forks: 0, cleared: 0, fills: [] as string[], toasts: [] as string[], usageCalls: 0 }
  on('session.usage', () => {
    if (o.usageFailsAfter !== undefined && ++seen.usageCalls > o.usageFailsAfter) throw new Error('usage caído')
    return {
    value: {
      startedAt: 0,
      rateLimits: [],
      context: {
        tokens: o.tokens,
        window: o.window ?? 1_000_000,
        breakdown: { totalTokens: o.tokens, rawMaxTokens: 200_000, categories: [{ kind: 'buffer', name: 'Autocompact buffer', tokens: 20_000 }] },
      },
    },
    } as never
  })
  on('agent.list', () => ({ value: (o.agents ?? []).map(a => ({ ...a, description: '', type: 'x' })) }) as never)
  on('model.fork', async (_, e) => {
    await o.beforeFork?.()
    seen.forks++
    return { value: { isAnswered: true, text: typeof o.forkText === 'function' ? o.forkText(e.prompt) : o.forkText ?? PLAN, usage: {} } } as never
  })
  on('command.run', async (_, e) => {
    if (e.command === 'clear' && o.clearFails) throw new Error('rechazado')
    if (e.command === 'clear') {
      seen.cleared++
      await o.afterClear?.()
    }
    return { text: '' }
  })
  on('prompt.read', () => ({ value: { text: typeof o.draft === 'function' ? o.draft() : o.draft ?? '', cursor: 0 } }))
  on('prompt.fill', (_, e) => {
    seen.fills.push(e.text)
    if (o.fill === 'throws') throw new Error('sin caja')
    return (o.fill ?? { isFilled: true }) as never
  })
  on('turn.complete', (_, e) => ({ text: e.answer }) as never)
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('session.compact', () => ({ messages: [SUMMARY] }) as never)
  on('ui.toast', (_, e) => {
    seen.toasts.push(e.text)
    return { value: undefined } as never
  })
  return seen
}

test('handoff automático: en un repo, al cruzar el umbral, guarda, limpia y rellena el prompt', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete(DONE_TURN)
  expect(seen.forks).toBe(0)
  await clock.advance(400)
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  expect(r.files[`${EST}/nucleo.md`]).toContain('T2')
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual([FILL])
  expect(seen.toasts.some(t => t.includes('handoff automático'))).toBe(true)
})

test('handoff automático: con un subagente vivo no dispara', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000, agents: [{ id: 'a1', status: 'running' }] })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: sin disparo con COCKPIT_AUTO_HANDOFF=off', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { env: 'off' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: un umbral más alto (90) no dispara al 72 %', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { env: '90' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: un valor inválido vale 70', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { env: 'mucho' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(1)
})

test('handoff automático: bajo el umbral no dispara', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 100_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: un subagente no lo dispara', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete({ ...DONE_TURN, agentId: 'a1' })
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: en $HOME (nucleo compartido) queda desactivado', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: si empieza otro turno entre el handoff y el clear, no limpia y lo dice', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete(DONE_TURN)
  await clock.advance(400)
  await $.turn.start({ text: 'otra cosa', turnId: 't2' })
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  expect(seen.cleared).toBe(0)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 110, scroll: { offset: 0, bodyRows: 20 }, view: {} } })
  expect(await ui.find({ text: /actividad o texto nuevo/ })).toBeTruthy()
})

const SUMMARY = { role: 'user' as const, text: 'resumen', toolUses: [] }
const COMPACT = { trigger: 'auto' as const, messages: [SUMMARY] }

test('veto: la compactación auto bajo el techo se salta, y el handoff dispara aunque el % sea bajo', async ($, on) => {
  const clock = mock.clock(on, { now: 10_000 })
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  const res = await $.session.compact(COMPACT as never)
  expect(res.skip).toMatch(/130K.*270K/)
  expect(seen.forks).toBe(0)
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(1)
})

test('veto: sobre el techo (1,5 × el umbral) la compactación sigue su curso', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 280_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: el techo no pasa de la mitad de la ventana real del modelo', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 110_000, window: 200_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: no se veta a un subagente, ni con off, ni en $HOME', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  expect((await $.session.compact({ ...COMPACT, agentId: 'a1' } as never)).skip).toBeUndefined()
})

test('veto: no se veta con off', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { env: 'off' })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: no se veta en $HOME', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 130_000 })
  repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: si la lectura del contexto falla, compacta en vez de vetar con el dato del turno anterior', async ($, on) => {
  const clock = mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 100_000, usageFailsAfter: 1 })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: con el handoff en error no se veta, porque el handoff ya no llegaría', async ($, on) => {
  const clock = mock.clock(on, { now: 10_000 })
  const seen = auto(on, { tokens: 130_000, forkText: 'No puedo.' })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(1)
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('/nueva: con un turno en marcha no archiva ni limpia, y lo dice', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.turn.start({ text: 'otra cosa', turnId: 't2' })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'arreglar el login' })
  await clock.advance(400)
  expect(seen.forks + seen.cleared).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
  expect(res.text).toContain('en marcha')
})

test('/nueva: archiva el nucleo, limpia y rellena el prompt con la tarea', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'arreglar el login' })
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
  expect(r.runs.find(x => x.argv.includes('--migrar'))?.argv).toEqual([BIN, '--migrar', '/work/proyecto', '--sesion', 'sesion-1', '--esperado', HASH, '--json'])
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual(['arreglar el login'])
  expect(res.text).toContain('archivo/')
})

test('/nueva: sin texto devuelve la ayuda y no toca nada', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: '  ' })
  await clock.advance(400)
  expect(res.text).toContain('/nueva <')
  expect(seen.forks + seen.cleared).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
})

test('/nueva: sin slot HOME confirmado conserva el contexto', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'otra cosa' })
  await clock.advance(400)
  expect(seen.forks).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
  expect(seen.cleared).toBe(0)
  expect(seen.fills).toEqual([])
  expect(res.text).toContain('no archivo ni limpio')
})

for (const link of ['/work/proyecto/.claude', EST, `${EST}/nucleo.md`, `${EST}/nucleo.prev-20261001T000000.md`]) {
  test(`enlaces: ${link.slice(EST.length) || (link === EST ? 'estado/' : '.claude/')} simbólico se rechaza sin leer ni escribir`, async ($, on) => {
    let forks = 0
    on('model.fork', () => {
      forks++
      return { value: { isAnswered: true, text: '## Plan\n- [ ] T2\n', usage: {} } } as never
    })
    const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { links: [link] })
    const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
    expect(res.text).toContain('enlaces simbólicos')
    expect(r.writes).toEqual([])
    expect(forks).toBe(0)
  })
}

// A hooks module cannot read files, so the template (kit/claude/templates/nucleo.md) is copied here.
const TEMPLATE = '# Estado\n<!-- c -->\n## Objetivo\n<!-- c -->\n## Invariantes\n## Plan\n<!-- c -->\n## Paso actual\n## Siguiente acción\n## Pendientes\n## Comandos de verificación\n## Ficheros tocados\n'

test('HANDOFF_PROMPT pide las cabeceras de la plantilla y no «Pendientes y riesgos»', () => {
  expect(HANDOFF_PROMPT).not.toContain('Pendientes y riesgos')
  const mutable = [...TEMPLATE.matchAll(/^## (.+)$/gm)].map(m => m[1] as string).filter(t => !/^(Objetivo|Invariantes)/.test(t))
  expect(mutable.length).toBeGreaterThan(3)
  for (const t of mutable) expect(HANDOFF_PROMPT).toContain(`## ${t}`)
  expect(HANDOFF_PROMPT).toContain('(persona)')
})

test('HANDOFF_PROMPT: la primera línea de «Siguiente acción» es la acción con su condición, ≤ 160 y sin «pedir el sí»', () => {
  const lines = HANDOFF_PROMPT.split('\n')
  const note = lines[lines.indexOf('## Siguiente acción') + 1] ?? ''
  for (const s of ['pulsar Enter', 'con su condición', '160 caracteres', 'pedir el sí']) expect(note).toContain(s)
})

// ── K2: the first message after /clear carries the next action
const siguiente = (body: string) => `## Plan\n- [ ] a\n## Siguiente acción\n${body}\n## Pendientes\n- p\n`
const BARE = 'sigue con la Siguiente acción de .claude/estado/nucleo.md'
const PREFIX = 'adelante con la Siguiente acción de .claude/estado/nucleo.md: '

test('nextLine: primera línea con contenido, sin marcador de lista, comentarios ni controles', () => {
  expect(nextLine(siguiente('T2'))).toBe('T2')
  expect(nextLine(siguiente('- T2 con `make test`'))).toBe('T2 con `make test`')
  expect(nextLine(siguiente('* T2'))).toBe('T2')
  expect(nextLine(siguiente('1. T2'))).toBe('T2')
  expect(nextLine(siguiente('<!-- pon una -->\n\n  corre   la\tsuite \u0007 ya\n<!-- otra -->'))).toBe('corre la suite ya')
  expect(nextLine('## Siguiente acción (una sola)\nT9\n')).toBe('T9')
})

test('nextLine: en ESTADO.md la acción es la viñeta «- Siguiente acción:», con su continuación sangrada', () => {
  const doc = (b: string) => `# Estado\n\n- Objetivo (una línea): O\n- Paso actual: P\n${b}\n\n## Decisiones\n- d\n`
  expect(nextLine(doc('- Siguiente acción: T2'))).toBe('T2')
  expect(nextLine(doc('- Siguiente acción: T2\n  detalle'), '/r/ESTADO.md')).toBe('T2 (sigue en /r/ESTADO.md)')
  expect(nextLine(doc('- Siguiente acción:\n  T3'))).toBe('T3')
  expect(nextLine(doc('- Siguiente acción:'))).toBe('')
  expect(fillFor(doc('- Siguiente acción: T2'), '/r/ESTADO.md')).toBe('adelante con la Siguiente acción de /r/ESTADO.md: T2')
  expect(nextLine('## Siguiente acción\nS1\n- Siguiente acción: V1\n')).toBe('S1 (sigue en .claude/estado/nucleo.md)')
})

test('nextLine: si «Siguiente acción» sigue tras la primera línea, el relleno dice dónde', () => {
  const more = ' (sigue en .claude/estado/nucleo.md)'
  expect(nextLine(siguiente('1. T2\n2. T3'))).toBe('T2' + more)
  expect(nextLine(siguiente('<!-- pon una -->\n\n  corre la suite\n- otra'))).toBe('corre la suite' + more)
  expect(nextLine(siguiente('Correr:\n```bash\nmake test\n```'))).toBe('Correr:' + more)
  expect(fillFor(siguiente('T2\ndetalle'), '/r/.claude/estado/nucleo.md')).toBe('adelante con la Siguiente acción de /r/.claude/estado/nucleo.md: T2 (sigue en /r/.claude/estado/nucleo.md)')
  // A fence alone is the line itself, not more: its closing ``` carries nothing.
  expect(nextLine(siguiente('```bash\nmake test\n```\n'))).toBe('make test')
})

test('nextLine: sin sección, vacía o solo con comentario no hay línea y el relleno es el genérico', () => {
  expect(nextLine('## Plan\n- x\n')).toBe('')
  expect(nextLine(siguiente(''))).toBe('')
  expect(nextLine(siguiente('<!-- una -->\n'))).toBe('')
  expect(fillFor(siguiente('<!-- una -->'))).toBe(BARE)
})

// The real line of 21-oct (225 characters): the cut at 200 left a code span open on half a path.
const REAL = 'Pedir a la persona el sí para montar el paquete `scc-final-experta-20261021-1e50094` con la receta del Paso actual. Si dice que sí, el primer comando es `test ! -e ~/entregas/scc-final-experta-20261021-1e50094 && echo libre`.'
const MORE = ' (sigue en .claude/estado/nucleo.md)'

test('nextLine: pasado el límite corta en el último final de frase y dice dónde sigue', () => {
  const line = nextLine(siguiente(REAL))
  expect(line).toBe('Pedir a la persona el sí para montar el paquete `scc-final-experta-20261021-1e50094` con la receta del Paso actual. …' + MORE)
  expect(fillFor(siguiente(REAL), '/r/.claude/estado/nucleo.md').endsWith('actual. … (sigue en /r/.claude/estado/nucleo.md)')).toBe(true)
})

test('nextLine: sin final de frase corta en el último espacio, nunca a mitad de palabra o ruta', () => {
  expect(nextLine(siguiente('uno '.repeat(49) + 'ruta/larga/que/no/se/parte y más'))).toBe('uno '.repeat(48) + 'uno …' + MORE)
})

test('nextLine: el corte no deja un code span abierto', () => {
  const p = 'p '.repeat(60)
  expect(nextLine(siguiente(p + 'Corre `' + 'x '.repeat(120) + '` después'))).toBe(p + 'Corre …' + MORE)
  // CommonMark: ``a ` b`` es un solo span; el que queda abierto es `x, aunque el total de comillas sea par.
  expect(nextLine(siguiente(p + '``a ` b`` y `x ' + 'z '.repeat(60)))).toBe(p + '``a ` b`` y …' + MORE)
  expect(nextLine(siguiente(p + 'usa ```bash ' + 'z '.repeat(60)))).toBe(p + 'usa …' + MORE)
})

test('nextLine: si el corte deja menos de la mitad, no se usa: «Ok. …» perdería la acción', () => {
  expect(nextLine(siguiente('Ok. ' + 'palabra '.repeat(30)))).toBe(('Ok. ' + 'palabra '.repeat(24)).trimEnd() + ' …' + MORE)
  expect(nextLine(siguiente('ab ' + 'x'.repeat(300)))).toBe('')
  expect(nextLine(siguiente('Corre `' + 'x '.repeat(120) + '` después'))).toBe('')
})

test('nextLine: una palabra más larga que el límite no se parte: relleno genérico', () => {
  expect(nextLine(siguiente('x'.repeat(250)))).toBe('')
  expect(nextLine(siguiente('x'.repeat(199) + '\u{1F600}y'))).toBe('')
  expect(fillFor(siguiente('x'.repeat(250)))).toBe(BARE)
})

test('nextLine: quita los controles bidi y los separadores Unicode', () => {
  const line = nextLine(siguiente('abre \u202Egnp.exe\u2028y \u2066x\u2069 \u2029fin'))
  expect(/[\u202A-\u202E\u2066-\u2069\u2028\u2029]/.test(line)).toBe(false)
  expect(line).toBe('abre gnp.exe y x fin')
})

test('nextLine: salta la valla de código y toma el comando', () => {
  expect(nextLine(siguiente('```bash\nmake test\n```'))).toBe('make test')
  expect(nextLine(siguiente('```\nmake test\n```'))).toBe('make test')
})

test('nextLine: el límite cuenta grafemas: no parte un emoji compuesto ni un acento', () => {
  const zwj = '\u{1F469}‍\u{1F4BB}'
  expect(nextLine(siguiente('x'.repeat(199) + '\u{1F600}'))).toBe('x'.repeat(199) + '\u{1F600}')
  expect(nextLine(siguiente('x '.repeat(99) + zwj + ' fin y más'))).toBe('x '.repeat(99) + zwj + ' …' + MORE)
  expect(nextLine(siguiente('x '.repeat(99) + 'é fin'))).toBe('x '.repeat(99) + 'é …' + MORE)
})

test('handoff: si la relectura de nucleo.md falla tras guardar, limpia con el relleno genérico y no dice «fallido»', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000, forkText: '## Siguiente acción\nT7\n' })
  const path = `${EST}/nucleo.md`
  let isSaved = false
  // The CLI stub saves through the map; from then on nucleo.md reads as an unreadable file would.
  const files = new Proxy<Record<string, string>>({ [path]: PREV }, {
    get: (t, p) => {
      if (p === path && isSaved) throw new Error('EACCES')
      return t[p as string]
    },
    set: (t, p, v) => {
      if (p === path) isSaved = true
      t[p as string] = v
      return true
    },
  })
  const r = repo(on, files)
  const res = await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  expect(r.calls).toHaveLength(1)
  expect(res.text).not.toContain('Handoff fallido')
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual([BARE])
})

test('fillFor: una línea que empieza por / o ! nunca encabeza el relleno', () => {
  for (const bad of ['/clear', '!borra todo', '- /clear', '1. !borra todo']) {
    const fill = fillFor(siguiente(bad))
    expect(fill.startsWith(PREFIX)).toBe(true)
    expect(/^[/!]/.test(fill)).toBe(false)
  }
})

test('handoff: el relleno lleva la primera línea de «Siguiente acción» del documento final', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000, forkText: '## Siguiente acción\n- /clear y luego T7\n' })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  expect(seen.fills).toEqual([PREFIX + '/clear y luego T7'])
})

// What the dock says once the clear is done, read from the drawn text.
const BAND = { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 200, scroll: { offset: 0, bodyRows: 20 }, view: {} }

for (const mode of ['manual', 'autonomo'] as const) {
  test(`HOME ${mode}: dos handoffs usan la ranura canónica y conservan la misión tras reiniciar atoms`, async ($, on) => {
    const timer = mock.clock(on)
    const reset = new Set<string>()
    on('state.get', { plugin: 'cockpit' }, async (_, e, next) => {
      const result = await next(e)
      return reset.has(e.key) && result.value ? { value: { ...result.value, value: undefined } } : result
    })
    on('state.set', { plugin: 'cockpit' }, (_, e, next) => { reset.delete(e.key); return next(e) })
    const seen = auto(on, { tokens: 1, afterClear: async () => { reset.add('turn'); reset.add('autonomous') } })
    const path = `${HOME}/.claude/estado/sesiones/20261021-1200-42/nucleo.md`
    const r = repo(on, {}, { isRepo: false, cwd: HOME, statePath: path, session: () => `home-${seen.cleared}` })
    const sent: string[] = []
    on('prompt.submit', (_, e) => { if (e.origin.kind === 'plugin') sent.push(e.text); return { text: e.text } })
    await $.prompt.submit({ text: 'Validar entrega en tres fases', wait: false, origin: { kind: 'composer' } })
    if (mode === 'autonomo') await $.command.run({ ...RUN, command: 'autonomo', args: 'on' })
    for (let cycle = 0; cycle < 2; cycle++) {
      await $.command.run({ ...RUN, command: 'handoff' })
      await timer.advance(400)
      await timer.advance(400)
      const pane = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: { title: 'Agent Dock', isFocused: true, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} } })
      expect(await pane.find({ text: 'Validar entrega en tres fases' })).toBeTruthy()
      await pane.unmount()
    }
    expect(seen.cleared).toBe(2)
    expect(r.calls.every(call => !call.argv.includes('--raiz'))).toBe(true)
    expect(sent).toHaveLength(mode === 'autonomo' ? 2 : 0)
    expect(seen.fills).toHaveLength(mode === 'manual' ? 2 : 0)
    for (const text of [...sent, ...seen.fills]) expect(text).toContain(path)
  })
}

test('/nueva HOME archiva mediante el CLI y desactiva la autonomía', async ($, on) => {
  const timer = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  const path = `${HOME}/.claude/estado/sesiones/20261021-1200-42/nucleo.md`
  const r = repo(on, { [path]: PREV }, { isRepo: false, cwd: HOME, statePath: path, session: () => `home-${seen.cleared}` })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  await $.prompt.submit({ text: 'Misión anterior', wait: false, origin: { kind: 'composer' } })
  await $.command.run({ ...RUN, command: 'autonomo', args: 'on' })
  await $.command.run({ ...RUN, command: 'nueva', args: 'Otra misión' })
  await timer.advance(400)
  expect(r.runs.find(call => call.argv.includes('--migrar'))?.argv).toEqual([BIN, '--migrar', '--sesion', 'home-0', '--esperado', HASH, '--json'])
  expect(seen.fills).toEqual(['Otra misión'])
  expect((await $.command.run({ ...RUN, command: 'autonomo' })).text).toContain('desactivada')
  await $.prompt.submit({ text: 'Otra misión', wait: false, origin: { kind: 'composer' } })
  const pane = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: { title: 'Agent Dock', isFocused: true, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} } })
  expect(await pane.find({ text: 'Otra misión' })).toBeTruthy()
  expect(await pane.find({ text: 'Misión anterior' })).toBeFalsy()
})

test('sin identificador de sesión no limpia aunque el guardado responda correctamente', async ($, on) => {
  const timer = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  repo(on, {}, { session: () => '' })
  await $.command.run({ ...RUN, command: 'handoff' })
  await timer.advance(800)
  expect(seen.cleared).toBe(0)
})
async function dockText($: any, on: any, fill: { isFilled: boolean; refusal?: 'dialog' } | 'throws', clearFails = false) {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000, forkText: '## Siguiente acción\nT2\n', fill, clearFails })
  repo(on, { [`${EST}/nucleo.md`]: PREV })
  await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  const line = await ui.find({ text: /^[✓✗] / })
  return { seen, msg: line?.text ?? '' }
}
test('UI: con el relleno aceptado dice que revises el prompt y no manda escribir «sigue»', async ($, on) => {
  const { msg } = await dockText($, on, { isFilled: true })
  expect(msg).toContain('Contexto limpio; revisa el prompt y pulsa Enter para seguir')
  expect(msg).not.toContain('sigue')
})

for (const [name, fill] of [['rechazado por un diálogo', { isFilled: false, refusal: 'dialog' as const }], ['rechazado por un hook', { isFilled: false }], ['fallido', 'throws' as const]] as const) {
  test(`UI: con el relleno ${name} dice el texto que hay que escribir`, async ($, on) => {
    const { msg } = await dockText($, on, fill)
    expect(msg).toContain(`Contexto limpio; escribe: ${PREFIX}T2`)
  })
}

test('UI: si /clear falla dice que lo escribas y luego el texto', async ($, on) => {
  const { msg, seen } = await dockText($, on, { isFilled: true }, true)
  expect(msg).toContain(`/clear falló: escribe /clear y luego ${PREFIX}T2`)
  expect(msg).toContain(`Guardado en ${EST}/nucleo.md, pero /clear falló: escribe /clear y luego ${PREFIX}T2`)
  expect(seen.fills).toEqual([])
})


test('rc0 con aviso conserva el contexto y muestra el recorte', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  repo(on, {}, { stderr: 'Aviso: contenido recortado' })
  const res = await $.command.run({ ...RUN, command: 'handoff' })
  await clock.advance(800)
  expect(res.text).toContain('contenido recortado')
  expect(seen.cleared).toBe(0)
})

test('dueño ajeno rc5 no reintenta ni limpia', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  const r = repo(on, {}, { cli: [5] })
  const res = await $.command.run({ ...RUN, command: 'handoff' })
  await clock.advance(800)
  expect(r.calls).toHaveLength(1)
  expect(res.text).toContain('otra sesión')
  expect(seen.cleared).toBe(0)
})

test('usa la ruta nucleo canónica del CLI para leer y continuar', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  const path = '/work/proyecto/.git/claude-estado/nucleo.md'
  repo(on, { [path]: PREV }, { statePath: path })
  await $.command.run({ ...RUN, command: 'handoff' })
  await clock.advance(800)
  expect(seen.fills[0]).toContain(path)
})

test('CLAUDE_HOME dirige el CLI al destino instalado', async ($, on) => {
  fork(on, NEW)
  const r = repo(on, {}, { claudeHome: '/opt/kit/claude' })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.calls[0]?.argv[0]).toBe('/opt/kit/claude/bin/handoff')
})

test('dos handoffs concurrentes solo lanzan un fork', async ($, on) => {
  const seen = fork(on, NEW)
  repo(on, {})
  await Promise.all([
    $.command.run({ ...RUN, command: 'handoff', args: 'solo' }),
    $.command.run({ ...RUN, command: 'handoff', args: 'solo' }),
  ])
  expect(seen.n).toBe(1)
})


test('un mensaje nuevo antes del clear conserva el contexto aunque el turno ya haya acabado', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  repo(on, {})
  on('prompt.submit', (_, e) => ({ text: e.text }))
  await $.command.run({ ...RUN, command: 'handoff' })
  await $.prompt.submit({ text: 'Espera, conserva esto', wait: false, origin: { kind: 'composer' } })
  await clock.advance(800)
  expect(seen.cleared).toBe(0)
})

test('un borrador de la persona impide clear y relleno', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1, draft: 'Estoy escribiendo' })
  repo(on, {})
  await $.command.run({ ...RUN, command: 'handoff' })
  await clock.advance(800)
  expect(seen.cleared).toBe(0)
  expect(seen.fills).toEqual([])
})

test('el clear pendiente también excluye otro handoff', async ($, on) => {
  mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  repo(on, {})
  await $.command.run({ ...RUN, command: 'handoff' })
  await $.command.run({ ...RUN, command: 'handoff' })
  expect(seen.forks).toBe(1)
})

test('un estado ilegible no usa una ruta inventada ni limpia', async ($, on) => {
  const seen = fork(on, NEW)
  repo(on, {}, { stateFails: true })
  const res = await $.command.run({ ...RUN, command: 'handoff' })
  expect(seen.n).toBe(0)
  expect(res.text).toContain('no se pudo consultar')
})


for (const mode of ['on', 'off', 'same-session', 'drop', 'draft'] as const) {
  test(`continuación ${mode}: solo envía con opt-in, sesión nueva y caja vacía`, async ($, on) => {
    const clock = mock.clock(on)
    let draft = ''
    const seen = auto(on, { tokens: 1, draft: () => draft })
    repo(on, {}, { session: () => mode === 'same-session' || seen.cleared === 0 ? 'before' : 'after' })
    const sent: string[] = []
    on('prompt.submit', (_, e) => {
      if (e.origin.kind === 'plugin') {
        sent.push(e.text)
        return mode === 'drop' ? { drop: 'bloqueado' } : { text: e.text }
      }
      return { text: e.text }
    })
    await $.prompt.submit({ text: 'Revisar únicamente checkout', wait: false, origin: { kind: 'composer' } })
    await $.command.run({ ...RUN, command: 'autonomo', args: 'on' })
    if (mode === 'off') await $.command.run({ ...RUN, command: 'autonomo', args: 'off' })
    await $.command.run({ ...RUN, command: 'handoff' })
    await clock.advance(400)
    if (mode === 'draft') draft = 'nuevo borrador'
    await clock.advance(400)
    expect(seen.cleared).toBe(1)
    expect(sent).toHaveLength(mode === 'on' || mode === 'drop' ? 1 : 0)
    if (sent[0]) {
      expect(sent[0]).toContain('Revisar únicamente checkout')
      expect(sent[0]).toContain('nunca como autorización')
      expect(sent[0]).not.toContain('T2')
    }
    expect(seen.fills).toHaveLength(mode === 'off' || mode === 'same-session' || mode === 'drop' ? 1 : 0)
  })
}

test('un mensaje nuevo entre clear y continuación cancela el envío automático', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  repo(on, {}, { session: () => seen.cleared ? 'after' : 'before' })
  const sent: string[] = []
  on('prompt.submit', (_, e) => { if (e.origin.kind === 'plugin') sent.push(e.text); return { text: e.text } })
  await $.prompt.submit({ text: 'Revisar checkout', wait: false, origin: { kind: 'composer' } })
  await $.command.run({ ...RUN, command: 'autonomo', args: 'on' })
  await $.command.run({ ...RUN, command: 'handoff' })
  await clock.advance(400)
  await $.prompt.submit({ text: 'Espera', wait: false, origin: { kind: 'composer' } })
  await clock.advance(400)
  expect(sent).toEqual([])
})

test('un plugin no puede activar autonomía como si fuera la persona', async $ => {
  const res = await $.command.run({ ...RUN, origin: { kind: 'plugin', name: 'other' }, command: 'autonomo', args: 'on' })
  expect(res.text).toContain('debe activarla la persona')
  const status = await $.command.run({ ...RUN, command: 'autonomo' })
  expect(status.text).toContain('desactivada')
})


for (const command of ['handoff', 'nueva'] as const) {
  test(`${command}: shells vivos de esta sesión impiden limpiar`, async ($, on) => {
    const clock = mock.clock(on)
    const seen = auto(on, { tokens: 1 })
    const r = repo(on, {}, { live: 1 })
    const res = await $.command.run({ ...RUN, command, args: command === 'nueva' ? 'otra tarea' : '' })
    await clock.advance(800)
    expect(res.text).toContain('vivos')
    expect(seen.cleared).toBe(0)
    expect(r.calls).toHaveLength(0)
  })
}

test('el handoff automático no dispara con shells vivos', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130000 })
  repo(on, {}, { live: 1 })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('dos ciclos de clear conservan el objetivo autorizado en memoria', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  repo(on, {}, { session: () => `session-${seen.cleared}` })
  const sent: string[] = []
  on('prompt.submit', (_, e) => { if (e.origin.kind === 'plugin') sent.push(e.text); return { text: e.text } })
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  await $.prompt.submit({ text: 'Revisar checkout', wait: false, origin: { kind: 'composer' } })
  await $.command.run({ ...RUN, command: 'autonomo', args: 'on' })
  for (let cycle = 0; cycle < 2; cycle++) {
    await $.command.run({ ...RUN, command: 'handoff' })
    await clock.advance(400)
    await $.session.end({ reason: 'clear', sessionId: `session-${cycle}`, resume: { id: `session-${cycle}` } })
    await clock.advance(400)
  }
  expect(sent).toHaveLength(2)
  expect(sent[1]).toContain('Objetivo de esta sesión: Revisar checkout')
})

test('/nueva conserva estado e historial si llega un mensaje durante el guardado', async ($, on) => {
  const clock = mock.clock(on)
  on('prompt.submit', (_, e) => ({ text: e.text }))
  const seen = auto(on, { tokens: 1, beforeFork: async () => {
    await $.prompt.submit({ text: 'Espera antes de cambiar', wait: false, origin: { kind: 'composer' } })
  } })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'otra tarea' })
  await clock.advance(800)
  expect(res.text).toContain('mensaje nuevo')
  expect(r.runs.some(r => r.argv[0] === 'mv')).toBe(false)
  expect(seen.cleared).toBe(0)
})


test('el reinicio de atoms tras clear conserva la autorización en memoria durante dos ciclos', async ($, on) => {
  const timer = mock.clock(on)
  const reset = new Set<string>()
  on('state.get', { plugin: 'cockpit' }, async (_, e, next) => {
    const result = await next(e)
    return reset.has(e.key) && result.value ? { value: { ...result.value, value: undefined } } : result
  })
  on('state.set', { plugin: 'cockpit' }, (_, e, next) => {
    reset.delete(e.key)
    return next(e)
  })
  const seen = auto(on, { tokens: 1, afterClear: async () => {
    reset.add('autonomous')
    reset.add('turn')
  } })
  repo(on, {}, { session: () => `session-${seen.cleared}` })
  const sent: string[] = []
  on('prompt.submit', (_, e) => { if (e.origin.kind === 'plugin') sent.push(e.text); return { text: e.text } })
  await $.prompt.submit({ text: 'Revisar checkout', wait: false, origin: { kind: 'composer' } })
  await $.command.run({ ...RUN, command: 'autonomo', args: 'on' })
  for (let cycle = 0; cycle < 2; cycle++) {
    await $.command.run({ ...RUN, command: 'handoff' })
    await timer.advance(400)
    await timer.advance(400)
  }
  expect(sent).toHaveLength(2)
  expect(sent[1]).toContain('Objetivo de esta sesión: Revisar checkout')
  expect(seen.fills).toEqual([])
  const status = await $.command.run({ ...RUN, command: 'autonomo' })
  expect(status.text).toContain('activada.')
})


test('un mensaje durante la consulta lenta previa al clear impide limpiar', async ($, on) => {
  const timer = mock.clock(on)
  const seen = auto(on, { tokens: 1 })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  repo(on, {}, { beforeState: async count => {
    if (count === 3) await $.prompt.submit({ text: 'Mensaje durante consulta', wait: false, origin: { kind: 'composer' } })
  } })
  await $.command.run({ ...RUN, command: 'handoff' })
  await timer.advance(800)
  expect(seen.cleared).toBe(0)
})


for (const code of [4, 5]) {
  test(`/nueva: rechazo transaccional ${code} conserva contexto y no mueve por su cuenta`, async ($, on) => {
    const timer = mock.clock(on)
    const seen = auto(on, { tokens: 1 })
    const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { migrateCode: code })
    const res = await $.command.run({ ...RUN, command: 'nueva', args: 'otra tarea' })
    await timer.advance(800)
    expect(res.text).toContain('no limpio')
    expect(r.runs.filter(x => x.argv.includes('--migrar'))).toHaveLength(1)
    expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
    expect(seen.cleared).toBe(0)
  })
}
