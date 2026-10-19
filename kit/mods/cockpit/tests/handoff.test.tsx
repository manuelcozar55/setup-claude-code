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
  opts: { links?: string[]; isRepo?: boolean; top?: string; cwd?: string; home?: string; env?: string; cli?: number[]; stderr?: string; noBin?: boolean } = {},
) {
  const runs: Run[] = []
  const writes: { path: string; text: string }[] = []
  const calls: { argv: readonly string[]; draft: string }[] = []
  const home = opts.home ?? HOME
  if (!opts.noBin) files[`${home}/.claude/bin/handoff`] = '#!/usr/bin/env bash\n'
  on('session.cwd', () => ({ value: opts.cwd ?? '/work/proyecto/sub' }))
  on('session.id', () => ({ value: 'sesion-1' }) as never)
  on('process.run', (_, e) => {
    runs.push(e)
    const a = e.argv.join(' ')
    if (a === 'printenv HOME') return ok(home)
    if (a === 'printenv COCKPIT_AUTO_HANDOFF') return opts.env ? ok(opts.env) : no()
    if (a.includes('--show-toplevel')) return opts.isRepo === false ? no() : ok(`${opts.top ?? '/work/proyecto'}\n`)
    if (e.argv[0] === 'find') return ok((opts.links ?? []).join('\n'))
    if (e.argv[0] === 'mktemp') return ok(`${TMP}\n`)
    if (e.argv[0] === 'rm') {
      for (const p of e.argv.slice(2)) delete files[p]
      return ok()
    }
    if (e.argv[0] === `${home}/.claude/bin/handoff` && e.argv[1] === '--estado') return no()
    if (e.argv[0] === `${home}/.claude/bin/handoff`) {
      const draft = files[TMP] ?? ''
      calls.push({ argv: e.argv, draft })
      const seq = opts.cli ?? [0]
      const code = seq[Math.min(calls.length - 1, seq.length - 1)] ?? 0
      if (code === 0) files[`${e.argv[e.argv.indexOf('--raiz') + 1]}/.claude/estado/nucleo.md`] = draft
      return { value: { exitCode: code, stdout: '', stderr: code ? (opts.stderr ?? '') : '' } } as never
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
  expect(r.calls[0]?.argv).toEqual([BIN, '--desde', TMP, '--raiz', '/work/proyecto', '--sesion', 'sesion-1'])
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
  expect(order.indexOf('chmod')).toBeLessThan(order.indexOf(BIN))
  expect(r.runs.find(x => x.argv[0] === 'rm')?.argv).toEqual(['rm', '-f', '--', TMP])
  expect(order.indexOf('rm')).toBeGreaterThan(order.indexOf(BIN))
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
  o: { tokens: number; window?: number; agents?: { id: string; status: string }[]; usageFailsAfter?: number; forkText?: string; fill?: { isFilled: boolean; refusal?: 'dialog' } | 'throws'; clearFails?: boolean },
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
  on('model.fork', () => {
    seen.forks++
    return { value: { isAnswered: true, text: o.forkText ?? PLAN, usage: {} } } as never
  })
  on('command.run', (_, e) => {
    if (e.command === 'clear' && o.clearFails) throw new Error('rechazado')
    if (e.command === 'clear') seen.cleared++
    return { text: '' }
  })
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
  expect(await ui.find({ text: /empezó otro turno/ })).toBeTruthy()
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
  const mv = r.runs.find(x => x.argv[0] === 'mv')
  expect(mv?.argv[mv.argv.length - 2]).toBe(`${EST}/nucleo.md`)
  expect(mv?.argv[mv.argv.length - 1]).toMatch(/\/estado\/archivo\/nucleo-\d{8}T\d{6}Z?\.md$/)
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

test('/nueva: en $HOME no hay handoff ni archivo, solo /clear y la tarea, con el aviso', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'otra cosa' })
  await clock.advance(400)
  expect(seen.forks).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual(['otra cosa'])
  expect(res.text).toContain('~')
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

// ── K2: the first message after /clear carries the next action
const siguiente = (body: string) => `## Plan\n- [ ] a\n## Siguiente acción\n${body}\n## Pendientes\n- p\n`
const BARE = 'sigue con la Siguiente acción de .claude/estado/nucleo.md'
const PREFIX = 'adelante con la Siguiente acción de .claude/estado/nucleo.md: '

test('nextLine: primera línea con contenido, sin marcador de lista, comentarios ni controles', () => {
  expect(nextLine(siguiente('T2'))).toBe('T2')
  expect(nextLine(siguiente('- T2 con `make test`'))).toBe('T2 con `make test`')
  expect(nextLine(siguiente('* T2'))).toBe('T2')
  expect(nextLine(siguiente('1. T2\n2. T3'))).toBe('T2')
  expect(nextLine(siguiente('<!-- pon una -->\n\n  corre   la\tsuite \u0007 ya\n- otra'))).toBe('corre la suite ya')
  expect(nextLine('## Siguiente acción (una sola)\nT9\n')).toBe('T9')
})

test('nextLine: sin sección, vacía o solo con comentario no hay línea y el relleno es el genérico', () => {
  expect(nextLine('## Plan\n- x\n')).toBe('')
  expect(nextLine(siguiente(''))).toBe('')
  expect(nextLine(siguiente('<!-- una -->\n'))).toBe('')
  expect(fillFor(siguiente('<!-- una -->'))).toBe(BARE)
})

test('nextLine: más de 200 caracteres se cortan con «…»', () => {
  const line = nextLine(siguiente('x'.repeat(250)))
  expect(line).toBe('x'.repeat(200) + '…')
  expect(fillFor(siguiente('x'.repeat(250)))).toBe(PREFIX + line)
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

test('nextLine: el corte a 200 no parte un par sustituto', () => {
  const line = nextLine(siguiente('x'.repeat(199) + '\u{1F600}'))
  expect(line).toBe('x'.repeat(199) + '\u{1F600}')
  const cut = nextLine(siguiente('x'.repeat(199) + '\u{1F600}y'))
  expect(cut).toBe('x'.repeat(199) + '\u{1F600}…')
  expect(/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/.test(cut)).toBe(false)
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
